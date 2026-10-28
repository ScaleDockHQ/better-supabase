import type { BlockSqlContext } from "../context.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { raise, revokeTable, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

export const COLLECTIONS = {
  id: "id",
  tenant: "organization_id",
  name: "name",
  description: "description",
  visibility: "visibility",
  priority: "priority",
  createdBy: "created_by",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

export const COLLECTION_GRANTS = {
  collection: "collection_id",
  user: "user_id",
  team: "team_id",
  createdAt: "created_at",
} as const;

/** How a collection shows up: in every search, to its grants, or nowhere. */
const VISIBILITIES = "'automatic', 'restricted', 'disabled'";

/**
 * `knowledge_collection_readable(id)`: whether the caller may read a
 * collection's documents. Restricted and disabled collections need a grant, the
 * manage permission or the service role.
 */
export function collectionReadable(
  ctx: BlockSqlContext,
  collection: string,
): string {
  return `${ctx.fn("knowledge_collection_readable")}(${collection})`;
}

/** Whether a search includes a collection: any but a disabled one. */
export function collectionSearched(
  ctx: BlockSqlContext,
  collection: string,
): string {
  return `exists (select 1 from ${ctx.table("collections")} kc where kc.${ctx.col("collections", "id")} = ${collection} and kc.${ctx.col("collections", "visibility")} <> 'disabled')`;
}

/** The priority of a document's collection, 0 without one. */
export function collectionPriority(
  ctx: BlockSqlContext,
  collection: string,
): string {
  return `coalesce((select kc.${ctx.col("collections", "priority")} from ${ctx.table("collections")} kc where kc.${ctx.col("collections", "id")} = ${collection}), 0)`;
}

/**
 * Knowledge collections: named groups of documents with a visibility, a
 * priority and grants to users or teams. A collection without a tenant is a
 * system collection the service role keeps, readable in every tenant.
 */
export function knowledgeCollectionsSql(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const k = (key: keyof typeof COLLECTIONS): string =>
    ctx.col("collections", key);

  const g = (key: keyof typeof COLLECTION_GRANTS): string =>
    ctx.col("collectionGrants", key);

  const collections = ctx.table("collections");
  const grants = ctx.table("collectionGrants");
  const permissions = moduleOperations("knowledge");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);

  const teams =
    ctx.installed("teams") && ctx.of("teams").mode !== "custom"
      ? ctx.of("teams")
      : undefined;

  const teamGrant = teams
    ? ` or (x.${g("team")} is not null and exists (select 1 from ${teams.table("members")} tm where tm.${teams.col("members", "team")}::text = x.${g("team")} and tm.${teams.col("members", "user")} = auth.uid()))`
    : "";

  const manages = (tenant: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.scope.can(tenant, manage)}))`;

  const json = (row: string): string =>
    `jsonb_build_object(${Object.entries(COLLECTIONS)
      .map(
        ([key, name]) =>
          // SAFETY: the keys are COLLECTIONS' own keys.
          `'${name}', ${row}.${k(key as keyof typeof COLLECTIONS)}`,
      )
      .join(", ")})`;

  const checkVisibility = (value: string): string => `
  if ${value} is null or ${value} not in (${VISIBILITIES}) then
    ${raise("visibility % is not automatic, restricted or disabled", "22023", "KNOWLEDGE_VISIBILITY", value)}
  end if;`;

  const loadManaged = (name: string): string => `
  select * into v_row from ${collections} x where x.${k("id")} = ${name}.collection_id for update;
  if not found or not ${manages(`v_row.${k("tenant")}`)} then
    ${raise("collection % not found", "P0002", "KNOWLEDGE_COLLECTION_NOT_FOUND", `${name}.collection_id`)}
  end if;`;

  return `-- Collections group documents. automatic ones show up in every search of
-- their tenant, restricted ones only for their grants and admins, disabled
-- ones in no search. A collection without a tenant is a system collection.
create table if not exists ${collections} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${id},
  ${k("name")} text not null check (length(${k("name")}) between 1 and 200),
  ${k("description")} text,
  ${k("visibility")} text not null default 'automatic' check (${k("visibility")} in (${VISIBILITIES})),
  ${k("priority")} integer not null default 0,
  ${k("createdBy")} uuid references auth.users (id) on delete set null,
  ${k("createdAt")} timestamptz not null default now(),
  ${k("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${ctx.naming.rename("knowledge_collections_name_key")} on ${collections} (${k("tenant")}, ${k("name")}) nulls not distinct;
alter table ${collections} enable row level security;
${revokeTable(collections)}
grant select on ${collections} to authenticated;
grant all on ${collections} to service_role;

create table if not exists ${grants} (
  ${g("collection")} uuid not null references ${collections} (${k("id")}) on delete cascade,
  ${g("user")} uuid references auth.users (id) on delete cascade,
  ${g("team")} text,
  ${g("createdAt")} timestamptz not null default now(),
  check ((${g("user")} is null) <> (${g("team")} is null))
);
create unique index if not exists ${ctx.naming.rename("knowledge_collection_grants_key")} on ${grants} (${g("collection")}, ${g("user")}, ${g("team")}) nulls not distinct;
create index if not exists ${ctx.naming.rename("knowledge_collection_grants_user_idx")} on ${grants} (${g("user")}) where ${g("user")} is not null;
alter table ${grants} enable row level security;
${revokeTable(grants)}
grant all on ${grants} to service_role;

-- Security definer, so the documents policy can check grants the caller
-- can't select.
create or replace function ${fn("knowledge_collection_readable")}(collection_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${collections} c
    where c.${k("id")} = knowledge_collection_readable.collection_id
      and (c.${k("tenant")} is null or ${SERVICE_CALLER} or ${ctx.scope.can(`c.${k("tenant")}`, read)})
      and (c.${k("visibility")} = 'automatic'
        or ${manages(`c.${k("tenant")}`)}
        or exists (
          select 1 from ${grants} x
          where x.${g("collection")} = c.${k("id")} and (x.${g("user")} = auth.uid()${teamGrant})
        ))
  )
$$;
${userGrant(`${fn("knowledge_collection_readable")}(uuid)`)}
${renderPolicy(makePolicy({ table: collections, name: ctx.naming.rename("knowledge_collections_read"), command: "select", roles: ["authenticated"], using: collectionReadable(ctx, k("id")) }), { drop: true, target: collections })}

-- Creates a collection. A tenant's admins create its collections; only the
-- service role creates a system collection (tenant null).
create or replace function ${fn("create_knowledge_collection")}(
  tenant ${id},
  name text,
  description text default null,
  visibility text default 'automatic',
  priority integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${collections}%rowtype;
begin
  if not ${manages("create_knowledge_collection.tenant")} then
    ${raise("only admins add knowledge collections", "42501", "KNOWLEDGE_FORBIDDEN")}
  end if;${checkVisibility("create_knowledge_collection.visibility")}
  insert into ${collections} (${k("tenant")}, ${k("name")}, ${k("description")}, ${k("visibility")}, ${k("priority")}, ${k("createdBy")})
  values (create_knowledge_collection.tenant, create_knowledge_collection.name, create_knowledge_collection.description, create_knowledge_collection.visibility, coalesce(create_knowledge_collection.priority, 0), auth.uid())
  returning * into v_row;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("create_knowledge_collection")}(${id}, text, text, text, integer)`)}

-- Changes the name, description, visibility or priority a patch names.
create or replace function ${fn("update_knowledge_collection")}(collection_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${collections}%rowtype;
  v_visibility text := coalesce(update_knowledge_collection.patch ->> 'visibility', 'automatic');
begin${loadManaged("update_knowledge_collection")}
  if update_knowledge_collection.patch ? 'visibility' then${checkVisibility("v_visibility")}
  end if;
  update ${collections} x set
    ${k("name")} = coalesce(update_knowledge_collection.patch ->> 'name', x.${k("name")}),
    ${k("description")} = case when update_knowledge_collection.patch ? 'description' then update_knowledge_collection.patch ->> 'description' else x.${k("description")} end,
    ${k("visibility")} = case when update_knowledge_collection.patch ? 'visibility' then v_visibility else x.${k("visibility")} end,
    ${k("priority")} = coalesce((update_knowledge_collection.patch ->> 'priority')::integer, x.${k("priority")}),
    ${k("updatedAt")} = now()
  where x.${k("id")} = v_row.${k("id")}
  returning * into v_row;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("update_knowledge_collection")}(uuid, jsonb)`)}

-- Deletes a collection; its documents stay, without a collection.
create or replace function ${fn("delete_knowledge_collection")}(collection_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${collections}%rowtype;
begin${loadManaged("delete_knowledge_collection")}
  delete from ${collections} x where x.${k("id")} = v_row.${k("id")};
  return true;
end;
$$;
${userGrant(`${fn("delete_knowledge_collection")}(uuid)`)}

-- The collections the caller can read in a tenant, system ones included,
-- highest priority first.
create or replace function ${fn("list_knowledge_collections")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("x")} order by x.${k("priority")} desc, x.${k("name")}), '[]')
  from ${collections} x
  where x.${k("tenant")} = list_knowledge_collections.tenant or x.${k("tenant")} is null
$$;
${userGrant(`${fn("list_knowledge_collections")}(${id})`)}

-- Grants a user or a team a restricted collection, or revokes it. Returns
-- whether anything changed.
create or replace function ${fn("set_knowledge_collection_grant")}(collection_id uuid, user_id uuid default null, team_id text default null, granted boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${collections}%rowtype;
  v_count integer;
begin${loadManaged("set_knowledge_collection_grant")}
  if (set_knowledge_collection_grant.user_id is null) = (set_knowledge_collection_grant.team_id is null) then
    ${raise("name a user or a team", "22023", "KNOWLEDGE_GRANT")}
  end if;
  if set_knowledge_collection_grant.granted then
    insert into ${grants} (${g("collection")}, ${g("user")}, ${g("team")})
    values (v_row.${k("id")}, set_knowledge_collection_grant.user_id, set_knowledge_collection_grant.team_id)
    on conflict do nothing;
  else
    delete from ${grants} x
    where x.${g("collection")} = v_row.${k("id")}
      and x.${g("user")} is not distinct from set_knowledge_collection_grant.user_id
      and x.${g("team")} is not distinct from set_knowledge_collection_grant.team_id;
  end if;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${userGrant(`${fn("set_knowledge_collection_grant")}(uuid, uuid, text, boolean)`)}

-- The grants of a collection, for its admins.
create or replace function ${fn("list_knowledge_collection_grants")}(collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${collections}%rowtype;
begin
  select * into v_row from ${collections} x where x.${k("id")} = list_knowledge_collection_grants.collection_id;
  if not found or not ${manages(`v_row.${k("tenant")}`)} then
    ${raise("collection % not found", "P0002", "KNOWLEDGE_COLLECTION_NOT_FOUND", "list_knowledge_collection_grants.collection_id")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('user_id', x.${g("user")}, 'team_id', x.${g("team")}, 'created_at', x.${g("createdAt")}) order by x.${g("createdAt")}), '[]')
    from ${grants} x where x.${g("collection")} = v_row.${k("id")}
  );
end;
$$;
${userGrant(`${fn("list_knowledge_collection_grants")}(uuid)`)}
`;
}
