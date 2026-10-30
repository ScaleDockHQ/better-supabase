import type { ActivitiesEvents } from "../../blocks/activities/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { guestOr } from "../guest-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
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
  NOTE_COLUMNS,
  NOTE_OPTIONS,
  noteColumnsSql,
  noteGuestSql,
  noteRules,
  notesContract,
  notesSql,
} from "./activities-notes.ts";
import {
  RECORDING_TABLES,
  recordingsContract,
  recordingsOn,
  recordingsSql,
} from "./activities-recordings.ts";
import { moduleOperations } from "./permissions-model.ts";
import { subjectTypeRenames } from "./subject-type-renames.ts";

/** The engagement types `options.types` falls back to. */
const ACTIVITY_TYPES = ["call", "email", "meeting", "note", "task"] as const;

const PAYLOAD = [
  "organizationId",
  "engagementId",
  "type",
  "subjectType",
  "subjectId",
] as const;

const EVENTS: BlockSqlEvents<ActivitiesEvents> = {
  "activity.logged": { subject: "engagements", payload: [...PAYLOAD] },
  "activity.updated": { subject: "engagements", payload: [...PAYLOAD] },
  "activity.completed": { subject: "engagements", payload: [...PAYLOAD] },
  "activity.deleted": { subject: "engagements", payload: [...PAYLOAD] },
  "activity.recorded": {
    subject: "engagements",
    payload: [...PAYLOAD, "recordingId"],
  },
  "activity.transcribed": {
    subject: "engagements",
    payload: [...PAYLOAD, "recordingId"],
    retries: true,
  },
  "activity.summarized": {
    subject: "engagements",
    payload: [...PAYLOAD],
    retries: true,
  },
  "activity.amended": {
    subject: "engagements",
    payload: [...PAYLOAD, "amendsId"],
  },
  "activity.error_marked": {
    subject: "engagements",
    payload: [...PAYLOAD, "reason"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    activity: {
      table: "engagements",
      singular: "activity",
      formerly: "engagement",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["body", "outcome"] },
      },
    },
  },
  events: EVENTS,
  hooks: ["before_activity_log", "after_activity_log"],
  options: ["types", "extraColumns", "recordings", "bookings", ...NOTE_OPTIONS],
  tables: {
    engagements: {
      name: "engagements",
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      app: {},
      optional: [
        "durationSeconds",
        "externalRef",
        "createdBy",
        "updatedAt",
        ...Object.keys(NOTE_COLUMNS),
      ],
      typed: ["type"],
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
        ...NOTE_COLUMNS,
      },
    },
    links: {
      name: "engagement_subjects",
      lifecycle: { tenant: "tenant", export: true },
      app: {},
      optional: ["position"],
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

/**
 * Row `alias` of logical table `table` as JSON keyed by the module's column
 * names. Over the app's table it lists the module's columns only, with null for
 * the ones the app lacks.
 */
function rowJson(ctx: BlockSqlContext, table: string, alias: string): string {
  if (ctx.owns(table)) {
    return `to_jsonb(${alias})`;
  }

  const columns = Object.entries(NAMES.tables[table]?.columns ?? {}).map(
    ([logical, name]) =>
      `${sqlString(name)}, ${ctx.has(table, logical) ? `${alias}.${ctx.col(table, logical)}` : "null"}`,
  );

  return `jsonb_build_object(${columns.join(", ")})`;
}

function types(ctx: BlockSqlContext): readonly string[] {
  const list = ctx.list("types", ACTIVITY_TYPES);

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
  const notes = noteRules(ctx);

  const optional = (
    table: string,
    column: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, column) ? `\n  ${definition(ctx.col(table, column))},` : "";

  const linkOrder = (alias: string): string =>
    ctx.has("links", "position")
      ? `${alias}.${l("position")}`
      : `${alias}.${l("subjectType")}, ${alias}.${l("subjectId")}`;

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

  const owned = (column: string): boolean => ctx.has("engagements", column);

  /** `, <column> = <value>` when the engagements table has `column`. */
  const set = (
    column: string,
    value: (name: string) => string,
    gap = " ",
  ): string =>
    owned(column) ? `,${gap}${e(column)} = ${value(e(column))}` : "";

  const typeText = (alias: string): string =>
    ctx.owns("engagements")
      ? `${alias}.${e("type")}`
      : `${alias}.${e("type")}::text`;

  const editable = (alias: string): string =>
    `(auth.role() = 'service_role' or ${owned("createdBy") ? `${alias}.${e("createdBy")} = auth.uid() or ` : ""}${alias}.${e("owner")} = auth.uid() or ${ctx.scope.can(`${alias}.${e("tenant")}`, manage)})`;

  /**
   * Row `p` (a prefix such as `x.`, or empty in a policy) is readable: its
   * tenant's readers see it when one of its records is readable, or it has
   * none, and a restricted one needs more (`noteRules`).
   */
  const readable = (p: string): string => {
    const member = notes.memberRead(p);

    return `${ctx.scope.check(`${p}${e("tenant")}`, read)} and (
  not exists (select 1 from ${t("links")} lx where lx.${l("engagement")} = ${p}${e("id")})
  or exists (select 1 from ${t("links")} lx where lx.${l("engagement")} = ${p}${e("id")} and ${canSubject}(lx.${l("subjectType")}, lx.${l("subjectId")}, 'read'))
)${member === "true" ? "" : ` and ${member}`}`;
  };

  /** Fails with ACTIVITY_LOCKED when the caller may edit `id` but it is locked. */
  const refuseLocked = (id: string): string =>
    notes.locked("x.") === "false"
      ? ""
      : `
  if exists (select 1 from ${t("engagements")} x where x.${e("id")} = ${id} and ${editable("x")} and ${notes.locked("x.")}) then
    ${fail("ACTIVITY_LOCKED", "the engagement is locked: add an addendum with amend_activity instead", "55000")}
  end if;`;

  const subjectsOf = (id: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object('type', sx.${l("subjectType")}, 'id', sx.${l("subjectId")}) order by ${linkOrder("sx")}) from ${t("links")} sx where sx.${l("engagement")} = ${id}), '[]'::jsonb)`;

  const row = (alias: string): string =>
    `${rowJson(ctx, "engagements", alias)} || jsonb_build_object('subjects', ${subjectsOf(`${alias}.${e("id")}`)}, 'overdue', ${alias}.${e("doneAt")} is null and ${alias}.${e("dueAt")} < now()${extraFieldsJson(alias, extras)})`;

  const setSubjects = (
    engagement: string,
    list: string,
    tenant: string,
  ): string => `
  if jsonb_typeof(coalesce(${list}, '[]')) <> 'array' then
    ${fail("ACTIVITY_SUBJECTS_INVALID", "subjects must be a list of { type, id }", "22023")}
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(${list}, '[]')) loop
    if not ${subjectInTenant(ctx, "(v_item ->> 'type')", "(v_item ->> 'id')", tenant)} then
      ${fail("ACTIVITY_SUBJECT_FORBIDDEN", "a subject is unknown or not readable in this organization", "42501")}
    end if;
  end loop;
  delete from ${t("links")} x where x.${l("engagement")} = ${engagement};
  insert into ${t("links")} (${l("tenant")}, ${l("engagement")}, ${l("subjectType")}, ${l("subjectId")}${ctx.has("links", "position") ? `, ${l("position")}` : ""})
  select ${tenant}, ${engagement}, s.value ->> 'type', s.value ->> 'id'${ctx.has("links", "position") ? ", s.ordinality::integer" : ""}
  from jsonb_array_elements(coalesce(${list}, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := ${subjectsOf(engagement)};
  v_first := v_subjects -> 0;`;

  const attrs = (name: string, key: string): string =>
    `${name}.attrs ->> ${sqlString(key)}`;

  const logged = (
    [
      ["tenant", "v_tenant"],
      ["type", ctx.cast("engagements", "type", "v_type")],
      ["title", "v_title"],
      ["body", attrs("log_activity", "body")],
      ["outcome", attrs("log_activity", "outcome")],
      ["owner", "v_owner"],
      ["dueAt", `(${attrs("log_activity", "dueAt")})::timestamptz`],
      ["doneAt", `(${attrs("log_activity", "doneAt")})::timestamptz`],
      [
        "durationSeconds",
        `(${attrs("log_activity", "durationSeconds")})::integer`,
      ],
      ["externalRef", attrs("log_activity", "externalRef")],
      ["createdBy", "auth.uid()"],
      [
        "audience",
        `coalesce(nullif(${attrs("log_activity", "audience")}, ''), 'team')`,
      ],
      ["restrictedRoles", `nullif(${notes.roles("log_activity")}, '{}')`],
      ["category", `nullif(${attrs("log_activity", "category")}, '')`],
      ["lockedAt", notes.lockAt("v_type", "now()")],
      ["goal", `nullif(${attrs("log_activity", "goalId")}, '')::uuid`],
    ] as const
  ).filter(([column]) => owned(column));

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
  ${e("doneAt")} timestamptz,${optional("engagements", "durationSeconds", (x) => `${x} integer check (${x} >= 0)`)}${optional("engagements", "externalRef", (x) => `${x} text`)}${optional("engagements", "createdBy", (x) => `${x} uuid`)}
  ${e("createdAt")} timestamptz not null default now()${owned("updatedAt") ? `,\n  ${e("updatedAt")} timestamptz not null default now()` : ""}
);
create index if not exists ${ctx.naming.rename("engagements_owner_open_idx")} on ${t("engagements")} (${e("tenant")}, ${e("owner")}, ${e("dueAt")}) where ${e("doneAt")} is null;
create index if not exists ${ctx.naming.rename("engagements_tenant_created_idx")} on ${t("engagements")} (${e("tenant")}, ${e("createdAt")} desc);
${owned("externalRef") ? `create unique index if not exists ${ctx.naming.rename("engagements_external_ref_idx")} on ${t("engagements")} (${e("tenant")}, ${e("externalRef")}) where ${e("externalRef")} is not null;` : ""}${addExtraColumns(t("engagements"), extras)}${noteColumnsSql(ctx)}
${lockTable(t("engagements"), { read: true })}
create table if not exists ${t("links")} (
  ${l("tenant")} ${ctx.idType} not null,
  ${l("engagement")} uuid not null references ${t("engagements")} (${e("id")}) on delete cascade,
  ${l("subjectType")} text not null,
  ${l("subjectId")} text not null,${optional("links", "position", (x) => `${x} integer not null default 1`)}
  primary key (${l("engagement")}, ${l("subjectType")}, ${l("subjectId")})
);${
        ctx.owns("links")
          ? ""
          : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("links").name}_subject_key`)} on ${t("links")} (${l("engagement")}, ${l("subjectType")}, ${l("subjectId")});`
      }
create index if not exists ${ctx.naming.rename("engagement_subjects_subject_idx")} on ${t("links")} (${l("subjectType")}, ${l("subjectId")});
${lockTable(t("links"), { read: true })}${noteGuestSql(ctx, notes)}
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none. A guest of a record reads its subject notes.
${renderPolicy(
  makePolicy({
    table: t("links"),
    name: `${ctx.tableName("links").name}_read`,
    command: "select",
    roles: ["authenticated"],
    using: guestOr(
      `${ctx.scope.check(l("tenant"), read)} and ${canSubject}(${l("subjectType")}, ${l("subjectId")}, 'read')`,
      [
        notes.guests
          ? `(${ctx.scope.guest(l("tenant"), l("subjectType"), l("subjectId"), "read")} and ${fn("engagement_guest_readable")}(${l("engagement")}))`
          : "false",
      ],
    ),
  }),
  { drop: true, target: t("links") },
)}
${renderPolicy(
  makePolicy({
    table: t("engagements"),
    name: `${ctx.tableName("engagements").name}_read`,
    command: "select",
    roles: ["authenticated"],
    using: guestOr(readable(""), [notes.guestRead("")]),
  }),
  { drop: true, target: t("engagements") },
)}
`
    : ""
}
-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function ${fn("log_activity")}(tenant ${ctx.idType}, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant ${ctx.idType} := log_activity.tenant;
  v_type text := ${attrs("log_activity", "type")};
  v_title text := nullif(trim(${attrs("log_activity", "title")}), '');
  v_owner uuid := coalesce(nullif(${attrs("log_activity", "ownerId")}, '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", write)}) then
    ${fail("ACTIVITY_FORBIDDEN", "not allowed to log engagements")}
  end if;
  if v_type is null or not (v_type = any (${typeList})) then
    ${fail("ACTIVITY_TYPE_INVALID", "unknown engagement type", "22023")}
  end if;
  if v_title is null then
    ${fail("ACTIVITY_TITLE_REQUIRED", "a title is required", "23502")}
  end if;${notes.validate("log_activity")}${
    owned("externalRef") && notes.locked("x.") !== "false"
      ? `
  if exists (select 1 from ${t("engagements")} x where x.${e("tenant")} = v_tenant and x.${e("externalRef")} = ${attrs("log_activity", "externalRef")} and ${notes.locked("x.")}) then
    ${fail("ACTIVITY_LOCKED", "the engagement is locked: add an addendum with amend_activity instead", "55000")}
  end if;`
      : ""
  }
  ${ctx.hook("before_activity_log", [
    [ctx.idType, "log_activity.tenant"],
    ["jsonb", "log_activity.attrs"],
    ["jsonb", "log_activity.subjects"],
  ])}
  insert into ${t("engagements")} (${logged.map(([column]) => e(column)).join(", ")})
  values (${logged.map(([, value]) => value).join(", ")})${
    owned("externalRef")
      ? `
  on conflict (${e("tenant")}, ${e("externalRef")}) where ${e("externalRef")} is not null do update set
    ${e("title")} = excluded.${e("title")}, ${e("body")} = excluded.${e("body")}, ${e("outcome")} = excluded.${e("outcome")},
    ${e("dueAt")} = excluded.${e("dueAt")}, ${e("doneAt")} = excluded.${e("doneAt")}${set("durationSeconds", (x) => `excluded.${x}`)}${set("updatedAt", () => "now()")}`
      : ""
  }
  returning ${e("id")} into v_id;${writeExtraColumns(t("engagements"), extras, "log_activity.attrs -> 'fields'", `x.${e("id")} = v_id`)}
  ${setSubjects("v_id", "log_activity.subjects", "v_tenant")}
  ${record("activity.logged", "v_id", "v_type", "v_tenant")}${notifyOwner}
  ${ctx.hook("after_activity_log", [["uuid", "v_id"]])}
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("log_activity")}(${ctx.idType}, jsonb, jsonb)`)}

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function ${fn("update_activity")}(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_activity.engagement;
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
    ${fail("ACTIVITY_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  if ${has("update_activity", "type")} and not (${attrs("update_activity", "type")} = any (${typeList})) then
    ${fail("ACTIVITY_TYPE_INVALID", "unknown engagement type", "22023")}
  end if;${notes.validate("update_activity")}${refuseLocked("v_id")}
  update ${t("engagements")} x set
    ${e("type")} = coalesce(${ctx.cast("engagements", "type", attrs("update_activity", "type"))}, x.${e("type")}),
    ${e("title")} = coalesce(nullif(trim(${attrs("update_activity", "title")}), ''), x.${e("title")}),
    ${["body", "outcome", "externalRef"]
      .filter(owned)
      .map(
        (key) =>
          `${e(key)} = case when ${has("update_activity", key)} then ${attrs("update_activity", key)} else x.${e(key)} end`,
      )
      .join(",\n    ")},
    ${e("owner")} = case when ${has("update_activity", "ownerId")} then nullif(${attrs("update_activity", "ownerId")}, '')::uuid else x.${e("owner")} end,
    ${e("dueAt")} = case when ${has("update_activity", "dueAt")} then (${attrs("update_activity", "dueAt")})::timestamptz else x.${e("dueAt")} end,
    ${e("doneAt")} = case when ${has("update_activity", "doneAt")} then (${attrs("update_activity", "doneAt")})::timestamptz else x.${e("doneAt")} end${set("durationSeconds", (x) => `case when ${has("update_activity", "durationSeconds")} then (${attrs("update_activity", "durationSeconds")})::integer else x.${x} end`, "\n    ")}${set("audience", (x) => `case when ${has("update_activity", "audience")} then coalesce(nullif(${attrs("update_activity", "audience")}, ''), 'team') else x.${x} end`, "\n    ")}${set("restrictedRoles", (x) => `case when ${has("update_activity", "restrictedRoles")} then nullif(${notes.roles("update_activity")}, '{}') else x.${x} end`, "\n    ")}${set("category", (x) => `case when ${has("update_activity", "category")} then nullif(${attrs("update_activity", "category")}, '') else x.${x} end`, "\n    ")}${set("goal", (x) => `case when ${has("update_activity", "goalId")} then nullif(${attrs("update_activity", "goalId")}, '')::uuid else x.${x} end`, "\n    ")}${set("lockedAt", (x) => `case when ${has("update_activity", "type")} then coalesce(x.${x}, ${notes.lockAt(attrs("update_activity", "type"), `x.${e("createdAt")}`)}) else x.${x} end`, "\n    ")}${set("updatedAt", () => "now()", "\n    ")}
  where x.${e("id")} = v_id
  returning x.${e("type")}, x.${e("title")}, x.${e("owner")} into v_type, v_title, v_owner;${writeExtraColumns(t("engagements"), extras, "update_activity.attrs -> 'fields'", `x.${e("id")} = v_id`)}
  if update_activity.subjects is not null then
    ${setSubjects("v_id", "update_activity.subjects", "v_tenant")}
  else
    v_subjects := ${subjectsOf("v_id")};
    v_first := v_subjects -> 0;
  end if;
  ${record("activity.updated", "v_id", "v_type", "v_tenant")}${notifyOwner}
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("update_activity")}(uuid, jsonb, jsonb)`)}

-- Marks an engagement done now (done true) or open again.
create or replace function ${fn("complete_activity")}(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_activity.engagement;
  v_tenant ${ctx.idType};
  v_type text;
  v_subjects jsonb := ${subjectsOf("complete_activity.engagement")};
  v_first jsonb := v_subjects -> 0;
begin${refuseLocked("v_id")}
  update ${t("engagements")} x set
    ${e("doneAt")} = case when complete_activity.done then coalesce(x.${e("doneAt")}, now()) end,
    ${e("outcome")} = coalesce(complete_activity.outcome, x.${e("outcome")})${set("updatedAt", () => "now()", "\n    ")}
  where x.${e("id")} = v_id and ${editable("x")}
  returning x.${e("tenant")}, x.${e("type")} into v_tenant, v_type;
  if v_tenant is null then
    ${fail("ACTIVITY_NOT_FOUND", "no such engagement you can edit", "P0002")}
  end if;
  if complete_activity.done then
    ${record("activity.completed", "v_id", "v_type", "v_tenant")}
  end if;
  return (select ${row("x")} from ${t("engagements")} x where x.${e("id")} = v_id);
end;
$$;
${userGrant(`${fn("complete_activity")}(uuid, boolean, text)`)}

create or replace function ${fn("delete_activity")}(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant ${ctx.idType};
  v_type text;
  v_subjects jsonb := ${subjectsOf("delete_activity.engagement")};
  v_first jsonb := v_subjects -> 0;
begin${refuseLocked("v_id")}
  delete from ${t("engagements")} x where x.${e("id")} = v_id and ${editable("x")}
  returning x.${e("tenant")}, x.${e("type")} into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  ${record("activity.deleted", "v_id", "v_type", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("delete_activity")}(uuid)`)}

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function ${fn("activities_of")}(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
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
    where k.${l("subjectType")} = activities_of.subject_type and k.${l("subjectId")} = activities_of.subject_id
      and (activities_of.types is null or ${typeText("x")} = any (activities_of.types))
      and (activities_of.before is null or coalesce(x.${e("doneAt")}, x.${e("dueAt")}, x.${e("createdAt")}) < activities_of.before)
    order by at desc, id desc
    limit ${pageSize("activities_of.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("activities_of")}(text, text, text[], timestamptz, integer)`)}

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function ${fn("next_activity")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${row("x")}
  from ${t("engagements")} x
  join ${t("links")} k on k.${l("engagement")} = x.${e("id")}
  where k.${l("subjectType")} = next_activity.subject_type and k.${l("subjectId")} = next_activity.subject_id
    and x.${e("doneAt")} is null and x.${e("dueAt")} is not null
  order by x.${e("dueAt")}, x.${e("id")}
  limit 1
$$;
${userGrant(`${fn("next_activity")}(text, text)`)}

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function ${fn("open_activities")}(tenant ${ctx.idType}, owner uuid, due_before timestamptz, page_size integer)
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
    where x.${e("tenant")} = open_activities.tenant
      and x.${e("owner")} = coalesce(open_activities.owner, auth.uid())
      and x.${e("doneAt")} is null
      and (open_activities.due_before is null or x.${e("dueAt")} < open_activities.due_before)
    order by x.${e("dueAt")} nulls last, x.${e("id")}
    limit ${pageSize("open_activities.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("open_activities")}(${ctx.idType}, uuid, timestamptz, integer)`)}
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
}${logsBookings(ctx, types(ctx)) ? bookingEngagementsSql(ctx) : ""}${notesSql(
    ctx,
    {
      rules: notes,
      readable: (alias) => readable(`${alias}.`),
      editable,
      record,
      row,
      subjectsOf,
      write,
    },
  )}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "log_activity",
      args: ["{id}", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "update_activity",
      args: ["uuid", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "complete_activity",
      args: ["uuid", "boolean", "text"],
      returns: "jsonb",
    },
    { name: "delete_activity", args: ["uuid"], returns: "boolean" },
    {
      name: "activities_of",
      args: ["text", "text", "text[]", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "next_activity", args: ["text", "text"], returns: "jsonb" },
    {
      name: "open_activities",
      args: ["{id}", "uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    ...(recordingsOn(ctx) ? recordingsContract() : []),
    ...notesContract(ctx),
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
  data: subjectTypeRenames,
};
