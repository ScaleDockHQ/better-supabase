import type { CollectionsEvents } from "../../blocks/collections/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";
import type { Subject } from "../subjects.ts";
import type { CollectionNames } from "./collections-functions.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { subjectCascades } from "../subjects.ts";
import {
  collectionExtras,
  collectionFunctions,
  savedItemFunctions,
  starFunctions,
} from "./collections-functions.ts";
import { moduleOperations } from "./permissions-model.ts";
import { callerTeamIdsSql } from "./team-ids.ts";

/** Who sees a collection: its owner, a team, or the whole tenant. */
const COLLECTION_SCOPES = ["user", "team", "tenant"] as const;

/**
 * The most ids one `add_collection_entries` or `remove_collection_entries` call
 * takes.
 */
const MAX_COLLECTION_IDS = 1000;

const ENTRY = [
  "organizationId",
  "collectionId",
  "subjectType",
  "subjectId",
] as const;

const EVENTS: BlockSqlEvents<CollectionsEvents> = {
  "collection.created": {
    subject: "collections",
    payload: ["organizationId", "collectionId", "subjectType", "name", "scope"],
  },
  "collection.archived": {
    subject: "collections",
    payload: ["organizationId", "collectionId", "subjectType", "name"],
  },
  "collection.entry_added": { subject: "collections", payload: [...ENTRY] },
  "collection.entry_removed": { subject: "collections", payload: [...ENTRY] },
  "saved_item.reminded": {
    subject: "saved-items",
    payload: [
      "organizationId",
      "savedItemId",
      "userId",
      "subjectType",
      "subjectId",
      "note",
      "remindAt",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    collection: {
      table: "collections",
      singular: "subject_collection",
      primary: true,
    },
  },
  events: EVENTS,
  hooks: [
    "before_collection_create",
    "after_collection_create",
    "before_collection_add",
    "after_collection_add",
  ],
  options: ["extraColumns"],
  tables: {
    collections: {
      name: "subject_collections",
      lifecycle: { tenant: "tenant", user: "owner", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        scope: "scope",
        owner: "owner_id",
        team: "team_id",
        name: "name",
        description: "description",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    entries: {
      name: "subject_collection_entries",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        collection: "collection_id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        rank: "rank",
        addedBy: "added_by",
        addedAt: "added_at",
      },
    },
    favorites: {
      name: "favorites",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        user: "user_id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        rank: "rank",
        createdAt: "created_at",
      },
    },
    savedItems: {
      name: "saved_items",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        user: "user_id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        note: "note",
        remindAt: "remind_at",
        remindedAt: "reminded_at",
        completedAt: "completed_at",
        createdAt: "created_at",
      },
    },
  },
};

const textList = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

function tables(ctx: BlockSqlContext, names: CollectionNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t } = names;
  const co = (column: string): string => names.c("collections", column);
  const en = (column: string): string => names.c("entries", column);
  const fa = (column: string): string => names.c("favorites", column);
  const sv = (column: string): string => names.c("savedItems", column);

  return `
create table if not exists ${t("collections")} (
  ${co("id")} uuid primary key default gen_random_uuid(),
  ${co("tenant")} ${ctx.idType} not null,
  ${co("subjectType")} text not null,
  ${co("scope")} text not null default 'user' check (${co("scope")} in (${textList(COLLECTION_SCOPES)})),
  ${co("owner")} uuid references auth.users (id) on delete cascade,
  ${co("team")} text,
  ${co("name")} text not null check (length(${co("name")}) between 1 and 120),
  ${co("description")} text check (length(${co("description")}) <= 2000),
  ${co("archivedAt")} timestamptz,
  ${co("createdBy")} uuid,
  ${co("createdAt")} timestamptz not null default now(),
  ${co("updatedAt")} timestamptz not null default now(),
  check (${co("scope")} <> 'user' or ${co("owner")} is not null),
  check (${co("scope")} <> 'team' or ${co("team")} is not null)
);
create index if not exists ${ctx.naming.rename("subject_collections_tenant_type_idx")} on ${t("collections")} (${co("tenant")}, ${co("subjectType")}, lower(${co("name")}));
create index if not exists ${ctx.naming.rename("subject_collections_owner_idx")} on ${t("collections")} (${co("owner")}) where ${co("owner")} is not null;${addExtraColumns(t("collections"), collectionExtras(ctx))}
${lockTable(t("collections"), { read: true })}

create table if not exists ${t("entries")} (
  ${en("collection")} uuid not null references ${t("collections")} (${co("id")}) on delete cascade,
  ${en("tenant")} ${ctx.idType} not null,
  ${en("subjectType")} text not null,
  ${en("subjectId")} text not null,
  ${en("rank")} text collate "C" not null,
  ${en("addedBy")} uuid,
  ${en("addedAt")} timestamptz not null default now(),
  primary key (${en("collection")}, ${en("subjectId")})
);
create index if not exists ${ctx.naming.rename("subject_collection_entries_rank_idx")} on ${t("entries")} (${en("collection")}, ${en("rank")}, ${en("subjectId")});
create index if not exists ${ctx.naming.rename("subject_collection_entries_subject_idx")} on ${t("entries")} (${en("subjectType")}, ${en("subjectId")});
${lockTable(t("entries"), { read: true })}

create table if not exists ${t("favorites")} (
  ${fa("user")} uuid not null references auth.users (id) on delete cascade,
  ${fa("tenant")} ${ctx.idType} not null,
  ${fa("subjectType")} text not null,
  ${fa("subjectId")} text not null,
  ${fa("rank")} text collate "C" not null,
  ${fa("createdAt")} timestamptz not null default now(),
  primary key (${fa("user")}, ${fa("subjectType")}, ${fa("subjectId")})
);
create index if not exists favorites_user_rank_idx on ${t("favorites")} (${fa("user")}, ${fa("tenant")}, ${fa("rank")});
create index if not exists favorites_subject_idx on ${t("favorites")} (${fa("subjectType")}, ${fa("subjectId")});
${lockTable(t("favorites"), { read: true })}

create table if not exists ${t("savedItems")} (
  ${sv("id")} uuid primary key default gen_random_uuid(),
  ${sv("user")} uuid not null references auth.users (id) on delete cascade,
  ${sv("tenant")} ${ctx.idType} not null,
  ${sv("subjectType")} text not null,
  ${sv("subjectId")} text not null,
  ${sv("note")} text check (length(${sv("note")}) <= 1000),
  ${sv("remindAt")} timestamptz,
  ${sv("remindedAt")} timestamptz,
  ${sv("completedAt")} timestamptz,
  ${sv("createdAt")} timestamptz not null default now(),
  unique (${sv("user")}, ${sv("subjectType")}, ${sv("subjectId")})
);
create index if not exists saved_items_user_idx on ${t("savedItems")} (${sv("user")}, ${sv("tenant")}, ${sv("createdAt")} desc, ${sv("id")} desc);
create index if not exists saved_items_subject_idx on ${t("savedItems")} (${sv("subjectType")}, ${sv("subjectId")});
create index if not exists saved_items_due_idx on ${t("savedItems")} (${sv("remindAt")}) where ${sv("remindedAt")} is null and ${sv("completedAt")} is null;
${lockTable(t("savedItems"), { read: true })}
`;
}

function policies(ctx: BlockSqlContext, names: CollectionNames): string {
  const { t, canSubject } = names;
  const co = (column: string): string => names.c("collections", column);
  const en = (column: string): string => names.c("entries", column);
  const fa = (column: string): string => names.c("favorites", column);
  const sv = (column: string): string => names.c("savedItems", column);

  return `
-- A collection is visible to its owner, its team's members or the whole
-- tenant. An entry is visible when its collection is and the caller can
-- read its record, so a shared list never shows a record to someone who
-- can't open it. Stars and saved items are the caller's own.
drop policy if exists ${ctx.naming.rename("subject_collections_read")} on ${t("collections")};
create policy ${ctx.naming.rename("subject_collections_read")} on ${t("collections")} for select to authenticated
using (${names.scope.check(co("tenant"), names.read)} and (
  (${co("scope")} = 'user' and ${co("owner")} = (select auth.uid()))
  or (${co("scope")} = 'team' and ${names.inTeam(co("team"))})
  or ${co("scope")} = 'tenant'
));
drop policy if exists ${ctx.naming.rename("subject_collection_entries_read")} on ${t("entries")};
create policy ${ctx.naming.rename("subject_collection_entries_read")} on ${t("entries")} for select to authenticated
using (${names.scope.check(en("tenant"), names.read)}
  and exists (select 1 from ${t("collections")} c where c.${co("id")} = ${en("collection")})
  and ${canSubject}(${en("subjectType")}, ${en("subjectId")}, 'read'));
drop policy if exists favorites_read on ${t("favorites")};
create policy favorites_read on ${t("favorites")} for select to authenticated
using (${fa("user")} = (select auth.uid())
  and ${names.scope.check(fa("tenant"), names.read)}
  and ${canSubject}(${fa("subjectType")}, ${fa("subjectId")}, 'read'));
drop policy if exists saved_items_read on ${t("savedItems")};
create policy saved_items_read on ${t("savedItems")} for select to authenticated
using (${sv("user")} = (select auth.uid())
  and ${names.scope.check(sv("tenant"), names.read)}
  and ${canSubject}(${sv("subjectType")}, ${sv("subjectId")}, 'read'));
`;
}

/** The registry types whose `cascade: true` deletes their entries and stars. */
function cascading(
  ctx: BlockSqlContext,
): readonly (readonly [string, Subject])[] {
  return registeredSubjects(ctx.subjects, ctx.naming)
    .filter((subject) => subject.config.cascade === true)
    .map((subject) => [
      subject.type,
      {
        table: subject.config.table,
        ...(subject.config.id === undefined ? {} : { id: subject.config.id }),
        cascade: true,
        extra: {},
      },
    ]);
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("collections");

  const teams = callerTeamIdsSql(ctx, layout);

  const subjectTypes = registeredSubjects(ctx.subjects, ctx.naming)
    .filter((subject) => subject.tenant !== undefined)
    .map((subject) => subject.type);

  const read = ctx.permission("read", keys.read);

  const names: CollectionNames = {
    scope: ctx.scope,
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read,
    write: ctx.permission("write", keys.write),
    share: ctx.permission("share", keys.share),
    inTeam: (value) => (teams === "" ? "false" : `${value} in (${teams})`),
    canSubject: ctx.of("subjects").fn("can_subject"),
    subjectTitle: ctx.of("subjects").fn("subject_title"),
    subjectUrl: ctx.of("subjects").fn("subject_url"),
    subjectTypes: `${sqlString(`{${subjectTypes.join(",")}}`)}::text[]`,
    maxIds: MAX_COLLECTION_IDS,
  };

  const en = (column: string): string => ctx.col("entries", column);
  const fa = (column: string): string => ctx.col("favorites", column);
  const sv = (column: string): string => ctx.col("savedItems", column);

  return `${schemaPreamble(ctx)}
-- Favorites (a member's starred records, ranked for a sidebar), lists (named,
-- static collections of one subject type) and saved items (a member's records
-- to come back to, with a reminder) on config.records records.
${tables(ctx, names)}${ctx.manages ? policies(ctx, names) : ""}${collectionFunctions(ctx, names)}${starFunctions(ctx, names)}${savedItemFunctions(ctx, names)}${subjectCascades(
    ctx,
    cascading(ctx),
    `delete from ${ctx.table("entries")} where ${en("subjectType")} = v_type and ${en("subjectId")} = v_id;
  delete from ${ctx.table("favorites")} where ${fa("subjectType")} = v_type and ${fa("subjectId")} = v_id;
  delete from ${ctx.table("savedItems")} where ${sv("subjectType")} = v_type and ${sv("subjectId")} = v_id;`,
  )}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(collectionExtras(ctx)).contract;

  return [
    {
      name: "create_collection",
      args: ["{id}", "text", "text", "text", "text", "text", ...extra],
      returns: "jsonb",
    },
    {
      name: "rename_collection",
      args: ["uuid", "text", "text", ...extra],
      returns: "jsonb",
    },
    {
      name: "archive_collection",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    {
      name: "list_collections",
      args: ["{id}", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "add_collection_entries",
      args: ["uuid", "text[]", "text"],
      returns: "jsonb",
    },
    {
      name: "remove_collection_entries",
      args: ["uuid", "text[]"],
      returns: "integer",
    },
    {
      name: "rank_collection_entry",
      args: ["uuid", "text", "text"],
      returns: "boolean",
    },
    {
      name: "subject_collection_entries",
      args: ["uuid", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "collection_subject_ids",
      args: ["uuid", "integer"],
      returns: "text[]",
    },
    { name: "collections_of", args: ["text", "text"], returns: "jsonb" },
    { name: "star_subject", args: ["{id}", "text", "text"], returns: "jsonb" },
    { name: "unstar_subject", args: ["text", "text"], returns: "boolean" },
    { name: "rank_star", args: ["text", "text", "text"], returns: "boolean" },
    { name: "starred_subjects", args: ["{id}", "text"], returns: "jsonb" },
    {
      name: "save_for_later",
      args: ["{id}", "text", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "complete_saved_item",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "remove_saved_item", args: ["uuid"], returns: "boolean" },
    {
      name: "list_saved_items",
      args: ["{id}", "boolean", "timestamptz", "uuid", "integer"],
      returns: "jsonb",
    },
    { name: "remind_due_saved_items", args: ["integer"], returns: "jsonb" },
  ];
}

const CONTRIBUTES: BlockContributes = {
  bulk: (own) => [
    {
      name: "collections.add",
      run: `perform ${own.fn("add_collection_entries")}((bulk_row.args ->> 'collectionId')::uuid, array[bulk_row.subject_id], bulk_row.subject_type);`,
    },
  ],
};

export const COLLECTIONS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "collections",
  scopes: ["tenant"],
  title: "Collections",
  description:
    "Favorites (a member's ranked stars on any registered record), lists (named, static collections of one subject type owned by a user, a team or the organization) and saved items (a member's records to come back to, with a note and a reminder), with entries hidden unless the caller can read their record.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["outbox", "teams"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
