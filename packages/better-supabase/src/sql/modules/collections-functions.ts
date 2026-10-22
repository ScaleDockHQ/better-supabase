import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { BlockSqlScope } from "../scope.ts";

import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";

export interface CollectionNames {
  /** The block's scope checks. */
  readonly scope: BlockSqlScope;
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly share: string;
  /**
   * SQL that is true when `value` (text) is one of the caller's teams; `false`
   * without `teams`.
   */
  readonly inTeam: (value: string) => string;
  readonly canSubject: string;
  readonly subjectTitle: string;
  readonly subjectUrl: string;
  /** The `text[]` of registered subject types that have a tenant. */
  readonly subjectTypes: string;
  readonly maxIds: number;
}

const SERVICE = "auth.role() = 'service_role'";

/** `options.extraColumns`, which the collections table gets. */
export const collectionExtras = (
  ctx: BlockSqlContext,
): readonly ExtraColumn[] =>
  ctx.extraColumns("collections", [
    "id",
    "scope",
    "name",
    "description",
    "fields",
  ]);

export function collectionFunctions(
  ctx: BlockSqlContext,
  names: CollectionNames,
): string {
  const { t, fn } = names;
  const co = (column: string): string => names.c("collections", column);
  const extras = collectionExtras(ctx);
  const createArgs = `${ctx.idType}, text, text, text, text, text`;

  const setExtras = (source: string, id: string): string =>
    writeExtraColumns(
      t("collections"),
      extras,
      source,
      `x.${co("id")} = ${id}`,
    );

  const en = (column: string): string => names.c("entries", column);

  // `subject_collections_read` for a row a security definer function has read.
  const maySee = (alias: string): string =>
    `(${SERVICE} or (${ctx.scope.can(`${alias}.${co("tenant")}`, names.read)} and (
      (${alias}.${co("scope")} = 'user' and ${alias}.${co("owner")} = auth.uid())
      or (${alias}.${co("scope")} = 'team' and ${names.inTeam(`${alias}.${co("team")}`)})
      or ${alias}.${co("scope")} = 'tenant')))`;

  // Renaming and archiving: the owner of a personal list, or collections.share.
  const mayManage = (alias: string): string =>
    `(${SERVICE}
    or (${alias}.${co("scope")} = 'user' and ${alias}.${co("owner")} = auth.uid() and ${ctx.scope.can(`${alias}.${co("tenant")}`, names.write)})
    or (${alias}.${co("scope")} <> 'user' and ${ctx.scope.can(`${alias}.${co("tenant")}`, names.share)}))`;

  // Adding, removing and ordering entries: anyone who sees the list and holds collections.write.
  const mayFill = (alias: string): string =>
    `(${SERVICE} or (${maySee(alias)} and ${ctx.scope.can(`${alias}.${co("tenant")}`, names.write)}))`;

  const json = (alias: string): string =>
    `jsonb_build_object(
    'id', ${alias}.${co("id")},
    'organizationId', ${alias}.${co("tenant")},
    'subjectType', ${alias}.${co("subjectType")},
    'scope', ${alias}.${co("scope")},
    'ownerId', ${alias}.${co("owner")},
    'teamId', ${alias}.${co("team")},
    'name', ${alias}.${co("name")},
    'description', ${alias}.${co("description")},
    'archivedAt', ${alias}.${co("archivedAt")},
    'createdBy', ${alias}.${co("createdBy")},
    'createdAt', ${alias}.${co("createdAt")},
    'updatedAt', ${alias}.${co("updatedAt")}${extraFieldsJson(alias, extras)})`;

  const entryRecord = (event: string): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', v_row.${co("tenant")}, 'collectionId', v_row.${co("id")}, 'subjectType', v_row.${co("subjectType")}, 'subjectId', v_id)`,
      subject: `'collections/' || v_row.${co("id")}::text`,
      tenant: `v_row.${co("tenant")}::text`,
      audit: false,
    });

  const load = (arg: string, lock: boolean): string => `
  select * into v_row from ${t("collections")} where ${co("id")} = ${arg}${lock ? " for update" : ""};
  if not found or not ${maySee("v_row")} then
    ${fail("COLLECTION_NOT_FOUND", "collection not found", "P0002")}
  end if;`;

  const fillable = `
  if not ${mayFill("v_row")} then
    ${fail("COLLECTION_FORBIDDEN", "not allowed to change this collection's entries")}
  end if;
  if v_row.${co("archivedAt")} is not null then
    ${fail("COLLECTION_ARCHIVED", "the collection is archived", "55000")}
  end if;`;

  const tooMany = (arg: string): string => `
  if cardinality(${arg}) > ${String(names.maxIds)} then
    ${fail("COLLECTION_TOO_MANY", `at most ${String(names.maxIds)} ids per call`, "22023")}
  end if;`;

  return `
-- A list of one subject type, owned by the caller (scope user), a team
-- they belong to, or the whole tenant. Shared scopes need collections.share.
${extraFieldsArg(extras).drop(fn("create_collection"), createArgs)}
create or replace function ${fn("create_collection")}(tenant ${ctx.idType}, subject_type text, name text, scope text, team text, description text${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_scope text := coalesce(create_collection.scope, 'user');
  v_name text := nullif(trim(create_collection.name), '');
  v_service boolean := ${SERVICE};
begin
  if v_scope not in ('user', 'team', 'tenant') then
    ${fail("COLLECTION_INVALID", "scope must be user, team or tenant", "22023")}
  end if;
  if create_collection.subject_type is null or not (create_collection.subject_type = any (${names.subjectTypes})) then
    ${fail("COLLECTION_SUBJECT_TYPE_UNKNOWN", "not a subject type in config.subjects", "22023")}
  end if;
  if v_name is null then
    ${fail("COLLECTION_NAME_REQUIRED", "a name is required", "23502")}
  end if;
  if not (v_service or ${ctx.scope.can("create_collection.tenant", names.write)}) then
    ${fail("COLLECTION_FORBIDDEN", "not allowed to create collections")}
  end if;
  if v_scope = 'user' and auth.uid() is null then
    ${fail("COLLECTION_INVALID", "a personal collection needs a signed-in user", "22023")}
  end if;
  if v_scope <> 'user' and not (v_service or ${ctx.scope.can("create_collection.tenant", names.share)}) then
    ${fail("COLLECTION_FORBIDDEN", "not allowed to share collections")}
  end if;
  if v_scope = 'team' then
    if create_collection.team is null then
      ${fail("COLLECTION_INVALID", "a team collection needs a team", "22023")}
    end if;
    if not (v_service or ${names.inTeam("create_collection.team")}) then
      ${fail("COLLECTION_FORBIDDEN", "not a member of this team")}
    end if;
  end if;
  ${ctx.hook("before_collection_create", [
    [ctx.idType, "create_collection.tenant"],
    ["text", "create_collection.subject_type"],
    ["text", "v_scope"],
  ])}
  insert into ${t("collections")} (${co("tenant")}, ${co("subjectType")}, ${co("scope")}, ${co("owner")}, ${co("team")}, ${co("name")}, ${co("description")}, ${co("createdBy")})
  values (create_collection.tenant, create_collection.subject_type, v_scope,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'team' then create_collection.team end,
    v_name, nullif(trim(create_collection.description), ''), auth.uid())
  returning ${co("id")} into v_id;${setExtras("create_collection.fields", "v_id")}
  ${ctx.record({
    type: "collection.created",
    payload: `jsonb_build_object('organizationId', create_collection.tenant, 'collectionId', v_id, 'subjectType', create_collection.subject_type, 'name', v_name, 'scope', v_scope)`,
    subject: `'collections/' || v_id::text`,
    tenant: "create_collection.tenant::text",
    audit: false,
  })}
  ${ctx.hook("after_collection_create", [["uuid", "v_id"]])}
  return (select ${json("x")} from ${t("collections")} x where x.${co("id")} = v_id);
end;
$$;
${userGrant(`${fn("create_collection")}(${createArgs}${extraFieldsArg(extras).type})`)}

-- A null name keeps it; an empty description clears it, a null one keeps it.
${extraFieldsArg(extras).drop(fn("rename_collection"), "uuid, text, text")}
create or replace function ${fn("rename_collection")}(collection uuid, name text, description text${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("collections")};
begin
  ${load("rename_collection.collection", true)}
  if not ${mayManage("v_row")} then
    ${fail("COLLECTION_FORBIDDEN", "not allowed to change this collection")}
  end if;
  if rename_collection.name is not null and nullif(trim(rename_collection.name), '') is null then
    ${fail("COLLECTION_NAME_REQUIRED", "a name is required", "23502")}
  end if;
  update ${t("collections")} x set
    ${co("name")} = coalesce(trim(rename_collection.name), x.${co("name")}),
    ${co("description")} = case when rename_collection.description is null then x.${co("description")}
      else nullif(trim(rename_collection.description), '') end,
    ${co("updatedAt")} = now()
  where x.${co("id")} = v_row.${co("id")};${setExtras("rename_collection.fields", `v_row.${co("id")}`)}
  return (select ${json("x")} from ${t("collections")} x where x.${co("id")} = v_row.${co("id")});
end;
$$;
${userGrant(`${fn("rename_collection")}(uuid, text, text${extraFieldsArg(extras).type})`)}

-- Archives a collection (archived true) or restores it. An archived
-- collection keeps its entries but takes no changes to them.
create or replace function ${fn("archive_collection")}(collection uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("collections")};
begin
  ${load("archive_collection.collection", true)}
  if not ${mayManage("v_row")} then
    ${fail("COLLECTION_FORBIDDEN", "not allowed to change this collection")}
  end if;
  update ${t("collections")} x set
    ${co("archivedAt")} = case when coalesce(archive_collection.archived, true) then coalesce(x.${co("archivedAt")}, now()) end,
    ${co("updatedAt")} = now()
  where x.${co("id")} = v_row.${co("id")};
  if coalesce(archive_collection.archived, true) and v_row.${co("archivedAt")} is null then
    ${ctx.record({
      type: "collection.archived",
      payload: `jsonb_build_object('organizationId', v_row.${co("tenant")}, 'collectionId', v_row.${co("id")}, 'subjectType', v_row.${co("subjectType")}, 'name', v_row.${co("name")})`,
      subject: `'collections/' || v_row.${co("id")}::text`,
      tenant: `v_row.${co("tenant")}::text`,
      audit: false,
    })}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("archive_collection")}(uuid, boolean)`)}

-- The collections the caller sees in a tenant, by name: every subject type
-- when subject_type is null, archived ones only with include_archived.
create or replace function ${fn("list_collections")}(tenant ${ctx.idType}, subject_type text, include_archived boolean)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("x")} order by lower(x.${co("name")}), x.${co("id")}), '[]'::jsonb)
  from ${t("collections")} x
  where x.${co("tenant")} = list_collections.tenant
    and (list_collections.subject_type is null or x.${co("subjectType")} = list_collections.subject_type)
    and (coalesce(list_collections.include_archived, false) or x.${co("archivedAt")} is null)
$$;
${userGrant(`${fn("list_collections")}(${ctx.idType}, text, boolean)`)}

-- Adds records to the end of a collection, in the order given. Ids already
-- in it are skipped; one the caller can't read fails the whole call.
-- subject_type, when given, must be the collection's.
create or replace function ${fn("add_collection_entries")}(collection uuid, subject_ids text[], subject_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("collections")};
  v_id text;
  v_last text;
  v_rank text;
  v_added text[] := '{}';
begin
  ${tooMany("add_collection_entries.subject_ids")}
  ${load("add_collection_entries.collection", true)}
  ${fillable}
  if add_collection_entries.subject_type is not null and add_collection_entries.subject_type <> v_row.${co("subjectType")} then
    ${fail("COLLECTION_SUBJECT_TYPE_MISMATCH", "the collection holds another subject type", "22023")}
  end if;
  ${ctx.hook("before_collection_add", [
    ["uuid", `v_row.${co("id")}`],
    ["text[]", "add_collection_entries.subject_ids"],
  ])}
  select max(e.${en("rank")}) into v_last from ${t("entries")} e where e.${en("collection")} = v_row.${co("id")};
  for v_id in
    select u.id from unnest(coalesce(add_collection_entries.subject_ids, '{}')) with ordinality u (id, n)
    where u.id is not null
    group by u.id order by min(u.n)
  loop
    if not ${subjectInTenant(ctx, `v_row.${co("subjectType")}`, "v_id", `v_row.${co("tenant")}`)} then
      ${fail("COLLECTION_SUBJECT_FORBIDDEN", "a record is unknown or not readable in this organization")}
    end if;
    v_rank := ${rankAfter("v_last")};
    insert into ${t("entries")} (${en("collection")}, ${en("tenant")}, ${en("subjectType")}, ${en("subjectId")}, ${en("rank")}, ${en("addedBy")})
    values (v_row.${co("id")}, v_row.${co("tenant")}, v_row.${co("subjectType")}, v_id, v_rank, auth.uid())
    on conflict do nothing;
    if found then
      v_last := v_rank;
      v_added := v_added || v_id;
      ${entryRecord("collection.entry_added")}
    end if;
  end loop;
  ${ctx.hook("after_collection_add", [
    ["uuid", `v_row.${co("id")}`],
    ["text[]", "v_added"],
  ])}
  return jsonb_build_object('added', to_jsonb(v_added));
end;
$$;
${userGrant(`${fn("add_collection_entries")}(uuid, text[], text)`)}

-- Removes the records the caller can read from a collection; returns how many.
create or replace function ${fn("remove_collection_entries")}(collection uuid, subject_ids text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("collections")};
  v_id text;
  v_count integer := 0;
begin
  ${tooMany("remove_collection_entries.subject_ids")}
  ${load("remove_collection_entries.collection", true)}
  ${fillable}
  for v_id in
    delete from ${t("entries")} e
    where e.${en("collection")} = v_row.${co("id")}
      and e.${en("subjectId")} = any (coalesce(remove_collection_entries.subject_ids, '{}'))
      and (${SERVICE} or ${names.canSubject}(e.${en("subjectType")}, e.${en("subjectId")}, 'read'))
    returning e.${en("subjectId")}
  loop
    v_count := v_count + 1;
    ${entryRecord("collection.entry_removed")}
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("remove_collection_entries")}(uuid, text[])`)}

create or replace function ${fn("rank_collection_entry")}(collection uuid, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("collections")};
begin
  if rank_collection_entry.rank is null or rank_collection_entry.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("COLLECTION_RANK_INVALID", "not a rank key", "22023")}
  end if;
  ${load("rank_collection_entry.collection", false)}
  ${fillable}
  update ${t("entries")} e set ${en("rank")} = rank_collection_entry.rank
  where e.${en("collection")} = v_row.${co("id")} and e.${en("subjectId")} = rank_collection_entry.subject_id;
  return found;
end;
$$;
${userGrant(`${fn("rank_collection_entry")}(uuid, text, text)`)}

-- A page of a collection's entries in rank order, with each record's title
-- and URL. after_rank and after_id continue after the previous page's last
-- entry. Entries whose record the caller can't read are left out.
create or replace function ${fn("collection_entries")}(collection uuid, after_rank text, after_id text, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.rank, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'collectionId', e.${en("collection")},
      'subjectType', e.${en("subjectType")},
      'subjectId', e.${en("subjectId")},
      'rank', e.${en("rank")},
      'addedBy', e.${en("addedBy")},
      'addedAt', e.${en("addedAt")},
      'title', ${names.subjectTitle}(e.${en("subjectType")}, e.${en("subjectId")}),
      'url', ${names.subjectUrl}(e.${en("subjectType")}, e.${en("subjectId")})
    ) as value, e.${en("rank")} as rank, e.${en("subjectId")} collate "C" as id
    from ${t("entries")} e
    where e.${en("collection")} = collection_entries.collection
      and (collection_entries.after_rank is null
        or (e.${en("rank")}, e.${en("subjectId")} collate "C") > (collection_entries.after_rank collate "C", coalesce(collection_entries.after_id, '') collate "C"))
    order by e.${en("rank")}, e.${en("subjectId")} collate "C"
    limit ${pageSize("collection_entries.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("collection_entries")}(uuid, text, text, integer)`)}

-- The ids of a collection's records the caller can read, in rank order, at
-- most max_ids (default 500, up to ${String(names.maxIds)}): a saved view's "in list" filter.
create or replace function ${fn("collection_subject_ids")}(collection uuid, max_ids integer)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.rank, p.id), '{}')
  from (
    select e.${en("subjectId")} collate "C" as id, e.${en("rank")} as rank
    from ${t("entries")} e
    where e.${en("collection")} = collection_subject_ids.collection
    order by e.${en("rank")}, e.${en("subjectId")} collate "C"
    limit ${pageSize("collection_subject_ids.max_ids", 500, names.maxIds)}
  ) p
$$;
${userGrant(`${fn("collection_subject_ids")}(uuid, integer)`)}

-- The active collections the caller sees that hold a record, by name.
create or replace function ${fn("collections_of")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("x")} order by lower(x.${co("name")}), x.${co("id")}), '[]'::jsonb)
  from ${t("collections")} x
  join ${t("entries")} e on e.${en("collection")} = x.${co("id")}
  where e.${en("subjectType")} = collections_of.subject_type
    and e.${en("subjectId")} = collections_of.subject_id
    and x.${co("archivedAt")} is null
$$;
${userGrant(`${fn("collections_of")}(text, text)`)}
`;
}

export function starFunctions(
  ctx: BlockSqlContext,
  names: CollectionNames,
): string {
  const { t, fn } = names;
  const fa = (column: string): string => names.c("favorites", column);

  const json = (alias: string): string =>
    `jsonb_build_object(
      'subjectType', ${alias}.${fa("subjectType")},
      'subjectId', ${alias}.${fa("subjectId")},
      'organizationId', ${alias}.${fa("tenant")},
      'rank', ${alias}.${fa("rank")},
      'starredAt', ${alias}.${fa("createdAt")})`;

  return `
-- Stars a record the caller can read, at the end of their favorites. A
-- record already starred keeps its place.
create or replace function ${fn("star_subject")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_last text;
  v_rank text;
begin
  if v_user is null then
    ${fail("FAVORITE_INVALID", "a star needs a signed-in user", "22023")}
  end if;
  if not ${ctx.scope.can("star_subject.tenant", names.read)} then
    ${fail("FAVORITE_FORBIDDEN", "not allowed to star records")}
  end if;
  if not ${subjectInTenant(ctx, "star_subject.subject_type", "star_subject.subject_id", "star_subject.tenant")} then
    ${fail("FAVORITE_SUBJECT_FORBIDDEN", "the record is unknown or not readable in this organization")}
  end if;
  if not exists (
    select 1 from ${t("favorites")} f
    where f.${fa("user")} = v_user and f.${fa("subjectType")} = star_subject.subject_type and f.${fa("subjectId")} = star_subject.subject_id
  ) then
    select max(f.${fa("rank")}) into v_last from ${t("favorites")} f
      where f.${fa("user")} = v_user and f.${fa("tenant")} = star_subject.tenant;
    v_rank := ${rankAfter("v_last")};
    insert into ${t("favorites")} (${fa("user")}, ${fa("tenant")}, ${fa("subjectType")}, ${fa("subjectId")}, ${fa("rank")})
    values (v_user, star_subject.tenant, star_subject.subject_type, star_subject.subject_id, v_rank)
    on conflict do nothing;
  end if;
  return (select ${json("f")} from ${t("favorites")} f
    where f.${fa("user")} = v_user and f.${fa("subjectType")} = star_subject.subject_type and f.${fa("subjectId")} = star_subject.subject_id);
end;
$$;
${userGrant(`${fn("star_subject")}(${ctx.idType}, text, text)`)}

create or replace function ${fn("unstar_subject")}(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${t("favorites")} f
  where f.${fa("user")} = auth.uid() and f.${fa("subjectType")} = unstar_subject.subject_type and f.${fa("subjectId")} = unstar_subject.subject_id;
  return found;
end;
$$;
${userGrant(`${fn("unstar_subject")}(text, text)`)}

create or replace function ${fn("rank_star")}(subject_type text, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if rank_star.rank is null or rank_star.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("FAVORITE_RANK_INVALID", "not a rank key", "22023")}
  end if;
  update ${t("favorites")} f set ${fa("rank")} = rank_star.rank
  where f.${fa("user")} = auth.uid() and f.${fa("subjectType")} = rank_star.subject_type and f.${fa("subjectId")} = rank_star.subject_id;
  return found;
end;
$$;
${userGrant(`${fn("rank_star")}(text, text, text)`)}

-- The caller's stars in a tenant in sidebar order, with each record's title
-- and URL: every subject type when subject_type is null.
create or replace function ${fn("starred_subjects")}(tenant ${ctx.idType}, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("f")} || jsonb_build_object(
      'title', ${names.subjectTitle}(f.${fa("subjectType")}, f.${fa("subjectId")}),
      'url', ${names.subjectUrl}(f.${fa("subjectType")}, f.${fa("subjectId")}))
    order by f.${fa("rank")}, f.${fa("subjectType")}, f.${fa("subjectId")} collate "C"), '[]'::jsonb)
  from ${t("favorites")} f
  where f.${fa("user")} = (select auth.uid())
    and f.${fa("tenant")} = starred_subjects.tenant
    and (starred_subjects.subject_type is null or f.${fa("subjectType")} = starred_subjects.subject_type)
$$;
${userGrant(`${fn("starred_subjects")}(${ctx.idType}, text)`)}
`;
}

/** The most saved items one `remind_due_saved_items` call claims. */
const MAX_DUE_SAVED_ITEMS = 500;

/**
 * Save for later: a member's personal list of records to come back to, each
 * with an optional note and reminder time.
 */
export function savedItemFunctions(
  ctx: BlockSqlContext,
  names: CollectionNames,
): string {
  const { t, fn } = names;
  const sv = (column: string): string => names.c("savedItems", column);

  const json = (alias: string): string =>
    `jsonb_build_object(
      'id', ${alias}.${sv("id")},
      'organizationId', ${alias}.${sv("tenant")},
      'userId', ${alias}.${sv("user")},
      'subjectType', ${alias}.${sv("subjectType")},
      'subjectId', ${alias}.${sv("subjectId")},
      'note', ${alias}.${sv("note")},
      'remindAt', ${alias}.${sv("remindAt")},
      'remindedAt', ${alias}.${sv("remindedAt")},
      'completedAt', ${alias}.${sv("completedAt")},
      'createdAt', ${alias}.${sv("createdAt")})`;

  return `
-- Saves a record the caller can read for later. Saving it again replaces the
-- note and reminder and reopens a completed item.
create or replace function ${fn("save_for_later")}(tenant ${ctx.idType}, subject_type text, subject_id text, note text default null, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_note text := nullif(btrim(save_for_later.note), '');
begin
  if v_user is null then
    ${fail("SAVED_ITEM_INVALID", "saving for later needs a signed-in user", "22023")}
  end if;
  if not ${ctx.scope.can("save_for_later.tenant", names.read)} then
    ${fail("SAVED_ITEM_FORBIDDEN", "not allowed to save records")}
  end if;
  if not ${subjectInTenant(ctx, "save_for_later.subject_type", "save_for_later.subject_id", "save_for_later.tenant")} then
    ${fail("SAVED_ITEM_SUBJECT_FORBIDDEN", "the record is unknown or not readable in this organization")}
  end if;
  if length(v_note) > 1000 then
    ${fail("SAVED_ITEM_INVALID", "a note holds at most 1000 characters", "22023")}
  end if;
  if save_for_later.remind_at is not null and save_for_later.remind_at <= now() then
    ${fail("SAVED_ITEM_INVALID", "the reminder time must be in the future", "22023")}
  end if;
  insert into ${t("savedItems")} (${sv("user")}, ${sv("tenant")}, ${sv("subjectType")}, ${sv("subjectId")}, ${sv("note")}, ${sv("remindAt")})
  values (v_user, save_for_later.tenant, save_for_later.subject_type, save_for_later.subject_id, v_note, save_for_later.remind_at)
  on conflict (${sv("user")}, ${sv("subjectType")}, ${sv("subjectId")}) do update
    set ${sv("note")} = excluded.${sv("note")},
      ${sv("remindAt")} = excluded.${sv("remindAt")},
      ${sv("remindedAt")} = null,
      ${sv("completedAt")} = null;
  return (select ${json("s")} from ${t("savedItems")} s
    where s.${sv("user")} = v_user and s.${sv("subjectType")} = save_for_later.subject_type and s.${sv("subjectId")} = save_for_later.subject_id);
end;
$$;
${userGrant(`${fn("save_for_later")}(${ctx.idType}, text, text, text, timestamptz)`)}

-- Marks one of the caller's saved items completed, or open again with
-- completed false.
create or replace function ${fn("complete_saved_item")}(item uuid, completed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update ${t("savedItems")} s
    set ${sv("completedAt")} = case when complete_saved_item.completed then coalesce(s.${sv("completedAt")}, now()) end
    where s.${sv("id")} = complete_saved_item.item and s.${sv("user")} = auth.uid();
  return found;
end;
$$;
${userGrant(`${fn("complete_saved_item")}(uuid, boolean)`)}

create or replace function ${fn("remove_saved_item")}(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${t("savedItems")} s
    where s.${sv("id")} = remove_saved_item.item and s.${sv("user")} = auth.uid();
  return found;
end;
$$;
${userGrant(`${fn("remove_saved_item")}(uuid)`)}

-- The caller's saved items in a tenant, the newest first, with each record's
-- title and URL: the open ones, or the completed ones with completed true.
create or replace function ${fn("list_saved_items")}(tenant ${ctx.idType}, completed boolean default false, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by created_at desc, id desc), '[]'::jsonb)
  from (
    select s.${sv("createdAt")} as created_at, s.${sv("id")} as id, ${json("s")} || jsonb_build_object(
        'title', ${names.subjectTitle}(s.${sv("subjectType")}, s.${sv("subjectId")}),
        'url', ${names.subjectUrl}(s.${sv("subjectType")}, s.${sv("subjectId")})) as item
    from ${t("savedItems")} s
    where s.${sv("user")} = (select auth.uid())
      and s.${sv("tenant")} = list_saved_items.tenant
      and (s.${sv("completedAt")} is not null) = coalesce(list_saved_items.completed, false)
      and (list_saved_items.before is null
        or (s.${sv("createdAt")}, s.${sv("id")}) < (list_saved_items.before, coalesce(list_saved_items.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by s.${sv("createdAt")} desc, s.${sv("id")} desc
    limit ${pageSize("list_saved_items.max_rows", 50, 200)}
  ) page
$$;
${userGrant(`${fn("list_saved_items")}(${ctx.idType}, boolean, timestamptz, uuid, integer)`)}

-- Service role. Claims the open saved items whose reminder time has passed,
-- records saved_item.reminded for each and returns them. A claimed item is not
-- returned again until it is saved with a new reminder.
create or replace function ${fn("remind_due_saved_items")}(max_rows integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("savedItems")}%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not ${SERVICE} then
    ${fail("SAVED_ITEM_FORBIDDEN", "only the service role sends saved item reminders")}
  end if;
  for v_row in
    update ${t("savedItems")} s set ${sv("remindedAt")} = now()
    where s.${sv("id")} in (
      select d.${sv("id")} from ${t("savedItems")} d
      where d.${sv("remindAt")} <= now() and d.${sv("remindedAt")} is null and d.${sv("completedAt")} is null
      order by d.${sv("remindAt")}, d.${sv("id")}
      limit ${pageSize("remind_due_saved_items.max_rows", 100, MAX_DUE_SAVED_ITEMS)}
      for update skip locked
    )
    returning s.*
  loop
    ${ctx.record({
      type: "saved_item.reminded",
      payload: `jsonb_strip_nulls(jsonb_build_object('organizationId', v_row.${sv("tenant")}, 'savedItemId', v_row.${sv("id")}, 'userId', v_row.${sv("user")}, 'subjectType', v_row.${sv("subjectType")}, 'subjectId', v_row.${sv("subjectId")}, 'note', v_row.${sv("note")}, 'remindAt', v_row.${sv("remindAt")}))`,
      subject: `'saved-items/' || v_row.${sv("id")}::text`,
      tenant: `v_row.${sv("tenant")}::text`,
      audit: false,
    })}
    v_out := v_out || jsonb_build_array(${json("v_row")});
  end loop;
  return v_out;
end;
$$;
revoke execute on function ${fn("remind_due_saved_items")}(integer) from public, anon, authenticated;
grant execute on function ${fn("remind_due_saved_items")}(integer) to service_role;
`;
}
