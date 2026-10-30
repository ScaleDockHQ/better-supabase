import type { BlockSqlContext } from "../context.ts";
import type { DriveKit } from "./drive-kit.ts";

import { fail, serviceGrant, sha256Hex } from "../shared.ts";
import { usable } from "./drive-kit.ts";

/**
 * `blocks.drive.options.sync.prune`: what a full listing does to nodes it no
 * longer lists.
 */
export type DrivePrune = "mark" | "delete";

/**
 * `options.sync.prune` of the drive in `ctx`: `delete` (the default) removes
 * unlisted nodes, `mark` keeps them and sets `missing_since` on their record in
 * the imports record map, so it needs the imports block (ADR 0147).
 */
export function drivePrune(ctx: BlockSqlContext): DrivePrune {
  const raw = ctx.option("sync");
  const where = "blocks.drive.options.sync";

  if (raw === undefined || raw === null) {
    return "delete";
  }

  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError(`${where} must be { prune: 'mark' | 'delete' }`);
  }

  const prune: unknown = new Map(Object.entries(raw)).get("prune");

  if (prune === undefined || prune === "delete") {
    return "delete";
  }

  if (prune !== "mark") {
    throw new TypeError(`${where}.prune must be 'mark' or 'delete'`);
  }

  if (usable(ctx, "imports") === undefined) {
    throw new TypeError(
      `${where}.prune 'mark' keeps its missing_since in the imports record map, so it needs the imports block`,
    );
  }

  return "mark";
}

/**
 * `drive_sync_batch`. With the imports block installed, every mirrored node has
 * an `import_records` row (`source = 'drive:<connection>'`, `entity =
 * 'drive_node'`, `scope = <drive>`) holding the hash of what the provider sent,
 * so a node whose hash is unchanged is not written and a full listing finds the
 * unlisted nodes by the record's `last_run_id`. Without it, the function keeps
 * its older behavior: every listed node is upserted and stamped with `sync_run`
 * in its metadata.
 */
export function syncBatchSql(kit: DriveKit): string {
  const { ctx, T, n, fn, d, c, has, binColumn, touch, C, D, typeLit } = kit;
  const imports = usable(ctx, "imports");
  const prune = drivePrune(ctx);
  const records = imports?.table("records");

  const x = (column: string): string =>
    imports === undefined ? column : imports.col("records", column);

  const live = binColumn ? ` and s.${n("deletedAt")} is null` : "";
  const source = ctx.cast("nodes", "source", "v_source");

  const content = `coalesce(item -> 'metadata', '{}'::jsonb) || jsonb_build_object('parentExternalId', nullif(item ->> 'parentExternalId', ''))`;

  const itemsTable =
    imports === undefined
      ? `create temporary table pg_temp.drive_sync_items on commit drop as
  select distinct on (item ->> 'externalId')
    item ->> 'externalId' as external_id,
    nullif(item ->> 'parentExternalId', '') as parent_external_id,
    left(regexp_replace(coalesce(nullif(btrim(item ->> 'name'), ''), 'Untitled'), '[/[:cntrl:]]', '-', 'g'), 240) as name,
    (case when item ->> 'kind' = 'folder' then 'folder' else 'file' end) as kind,
    ${content} || jsonb_build_object('syncRun', drive_sync_batch.sync_run) as metadata,
    coalesce((item ->> 'removed')::boolean, false) as removed
  from jsonb_array_elements(coalesce(drive_sync_batch.items, '[]'::jsonb)) with ordinality as entry(item, position)
  where nullif(item ->> 'externalId', '') is not null
  order by item ->> 'externalId', position desc;`
      : `create temporary table pg_temp.drive_sync_items on commit drop as
  select q.*,
    (rec.${x("id")} is null or rec.${x("contentHash")} <> q.hash or node.${n("id")} is null) as changed
  from (
    select b.*, ${sha256Hex(`b.kind || chr(31) || b.name || chr(31) || coalesce(b.parent_external_id, '') || chr(31) || b.metadata::text`)} as hash
    from (
      select distinct on (item ->> 'externalId')
        item ->> 'externalId' as external_id,
        nullif(item ->> 'parentExternalId', '') as parent_external_id,
        left(regexp_replace(coalesce(nullif(btrim(item ->> 'name'), ''), 'Untitled'), '[/[:cntrl:]]', '-', 'g'), 240) as name,
        (case when item ->> 'kind' = 'folder' then 'folder' else 'file' end) as kind,
        ${content} as metadata,
        coalesce((item ->> 'removed')::boolean, false) as removed
      from jsonb_array_elements(coalesce(drive_sync_batch.items, '[]'::jsonb)) with ordinality as entry(item, position)
      where nullif(item ->> 'externalId', '') is not null
      order by item ->> 'externalId', position desc
    ) b
  ) q
  left join ${records} rec
    on rec.${x("tenant")} = v_drive.${d("tenant")}
    and rec.${x("source")} = v_record_source
    and rec.${x("scope")} = v_scope
    and rec.${x("entity")} = 'drive_node'
    and rec.${x("externalKey")} = q.external_id
    and rec.${x("role")} = 'primary'
  left join ${T} node
    on node.${n("id")}::text = rec.${x("subjectId")}
    and node.${n("drive")} = drive_sync_batch.drive;`;

  const upsertWhere =
    imports === undefined
      ? "where not item.removed"
      : "where not item.removed and item.changed";

  const recordWrites =
    imports === undefined
      ? ""
      : `
  insert into ${records} (${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")}, ${x("subjectType")}, ${x("subjectId")}, ${x("contentHash")}, ${x("firstRun")}, ${x("lastRun")}, ${x("subjectUpdatedAt")})
  select v_drive.${d("tenant")}, v_record_source, v_scope, 'drive_node', item.external_id, 'primary', ${typeLit}, s.${n("id")}::text, item.hash, v_run_id, v_run_id, now()
  from pg_temp.drive_sync_items item
  join ${T} s
    on s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = ${source}
    and s.${n("externalId")} = item.external_id${live}
  where not item.removed and item.changed
  on conflict (${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")}) do update set
    ${x("subjectType")} = excluded.${x("subjectType")},
    ${x("subjectId")} = excluded.${x("subjectId")},
    ${x("contentHash")} = excluded.${x("contentHash")},
    ${x("lastRun")} = excluded.${x("lastRun")},
    ${x("subjectUpdatedAt")} = excluded.${x("subjectUpdatedAt")},
    ${x("missingSince")} = null;
  if drive_sync_batch.sync_run is not null then
    update ${records} r
    set ${x("lastRun")} = v_run_id, ${x("missingSince")} = null
    from pg_temp.drive_sync_items item
    where not item.removed and not item.changed
      and r.${x("tenant")} = v_drive.${d("tenant")}
      and r.${x("source")} = v_record_source
      and r.${x("scope")} = v_scope
      and r.${x("entity")} = 'drive_node'
      and r.${x("externalKey")} = item.external_id
      and r.${x("role")} = 'primary'
      and (r.${x("lastRun")} is distinct from v_run_id or r.${x("missingSince")} is not null);
  end if;`;

  const pruneBlock =
    imports === undefined
      ? `
  if drive_sync_batch.prune and drive_sync_batch.sync_run is not null then
    delete from ${T} s
    where s.${n("drive")} = drive_sync_batch.drive
      and s.${n("source")} = ${source}
      and coalesce(s.${n("externalMetadata")} ->> 'syncRun', '') <> drive_sync_batch.sync_run
      and not ${fn("drive_node_held")}(s.${n("id")});
  end if;`
      : prune === "delete"
        ? `
  if drive_sync_batch.prune and drive_sync_batch.sync_run is not null then
    delete from ${T} s
    where s.${n("drive")} = drive_sync_batch.drive
      and s.${n("source")} = ${source}
      and not exists (
        select 1 from ${records} r
        where r.${x("tenant")} = v_drive.${d("tenant")}
          and r.${x("source")} = v_record_source
          and r.${x("scope")} = v_scope
          and r.${x("entity")} = 'drive_node'
          and r.${x("subjectId")} = s.${n("id")}::text
          and r.${x("lastRun")} = v_run_id
      )
      and not ${fn("drive_node_held")}(s.${n("id")});
    get diagnostics v_removed = row_count;
    v_deleted := v_deleted + v_removed;
  end if;`
        : `
  if drive_sync_batch.prune and drive_sync_batch.sync_run is not null then
    insert into ${records} (${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")}, ${x("subjectType")}, ${x("subjectId")}, ${x("contentHash")}, ${x("firstRun")}, ${x("lastRun")}, ${x("missingSince")})
    select v_drive.${d("tenant")}, v_record_source, v_scope, 'drive_node', s.${n("externalId")}, 'primary', ${typeLit}, s.${n("id")}::text, '', v_run_id, v_run_id, now()
    from ${T} s
    where s.${n("drive")} = drive_sync_batch.drive
      and s.${n("source")} = ${source}
      and s.${n("externalId")} is not null${live}
      and not exists (
        select 1 from ${records} r
        where r.${x("tenant")} = v_drive.${d("tenant")}
          and r.${x("source")} = v_record_source
          and r.${x("scope")} = v_scope
          and r.${x("entity")} = 'drive_node'
          and r.${x("externalKey")} = s.${n("externalId")}
          and r.${x("role")} = 'primary'
      )
    on conflict do nothing;
    update ${records} r set ${x("missingSince")} = coalesce(r.${x("missingSince")}, now())
    where r.${x("tenant")} = v_drive.${d("tenant")}
      and r.${x("source")} = v_record_source
      and r.${x("scope")} = v_scope
      and r.${x("entity")} = 'drive_node'
      and r.${x("lastRun")} <> v_run_id
      and r.${x("missingSince")} is null;
  end if;`;

  const cleanup =
    imports === undefined
      ? ""
      : `
  if v_deleted > 0 then
    delete from ${records} r
    where r.${x("tenant")} = v_drive.${d("tenant")}
      and r.${x("source")} = v_record_source
      and r.${x("scope")} = v_scope
      and r.${x("entity")} = 'drive_node'
      and not exists (select 1 from ${T} s where s.${n("id")}::text = r.${x("subjectId")});
  end if;`;

  const countDeleted = (): string =>
    imports === undefined
      ? ""
      : `
  get diagnostics v_removed = row_count;
  v_deleted := v_deleted + v_removed;`;

  const declare =
    imports === undefined
      ? ""
      : `
  v_record_source text;
  v_scope text;
  v_run_id uuid;
  v_removed integer := 0;
  v_deleted integer := 0;`;

  const identity =
    imports === undefined
      ? ""
      : `
  v_record_source := 'drive:' || v_connection.${c("id")}::text;
  v_scope := drive_sync_batch.drive::text;
  v_run_id := md5(v_record_source || ':' || coalesce(drive_sync_batch.sync_run, ''))::uuid;`;

  return `
-- Applies one page of provider changes to a connected drive mirror. Items
-- carry the provider id, parent provider id, name, kind and metadata; removed
-- items are deleted with their subtree. Items whose parent is the provider
-- root become top-level nodes, and top-level nodes with any other parent are
-- dropped, so the mirror only holds the tree under root_external_id. A full
-- listing carries sync_run, and its final call passes prune to remove every
-- mirrored node that listing didn't reach${
    imports === undefined
      ? ""
      : `. Nodes are tracked in the imports record map by content hash: a node
-- whose hash is unchanged is not written, and the return value counts the
-- nodes written. options.sync.prune = 'mark' keeps unlisted nodes and sets
-- missing_since on their record instead of deleting them. Legal holds win`
  }.
create or replace function ${fn("drive_sync_batch")}(drive uuid, items jsonb, root_external_id text, sync_run text default null, prune boolean default false, cursor text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_drive ${D}%rowtype;
  v_connection ${C}%rowtype;
  v_source text;
  v_count integer := 0;${declare}
begin
  select * into v_drive from ${D} d where d.${d("id")} = drive_sync_batch.drive for update;
  if not found or v_drive.${d("connection")} is null then
    ${fail("DRIVE_NOT_CONNECTED", "drive is not a connected drive", "P0002")}
  end if;
  select * into v_connection from ${C} c where c.${c("id")} = v_drive.${d("connection")};
  if not found then
    ${fail("DRIVE_CONNECTION_NOT_FOUND", "connection not found", "P0002")}
  end if;
  v_source := v_connection.${c("provider")};${identity}
  ${itemsTable}
  delete from ${T} s
  using pg_temp.drive_sync_items item
  where item.removed
    and s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = ${source}
    and s.${n("externalId")} = item.external_id${
      binColumn
        ? `
    and s.${n("deletedAt")} is null`
        : ""
    }
    and not ${fn("drive_node_held")}(s.${n("id")});${countDeleted()}
  insert into ${T} (${n("tenant")}, ${n("drive")}, ${n("parent")}, ${n("kind")}, ${n("name")}, ${n("source")}, ${n("externalId")}, ${n("externalMetadata")}${has("createdBy") ? `, ${n("createdBy")}` : ""})
  select
    v_drive.${d("tenant")},
    drive_sync_batch.drive,
    null,
    ${ctx.cast("nodes", "kind", "item.kind")},
    item.name,
    ${source},
    item.external_id,
    item.metadata${has("createdBy") ? `, v_drive.${d("owner")}` : ""}
  from pg_temp.drive_sync_items item
  ${upsertWhere}
  on conflict (${n("drive")}, ${n("source")}, ${n("externalId")}) where ${n("externalId")} is not null${binColumn ? ` and ${n("deletedAt")} is null` : ""}
  do update set
    ${n("kind")} = excluded.${n("kind")},
    ${n("name")} = excluded.${n("name")},
    ${n("externalMetadata")} = excluded.${n("externalMetadata")}${
      touch
        ? `,
    ${n("updatedAt")} = now()`
        : ""
    };
  get diagnostics v_count = row_count;
  update ${T} s
  set ${n("parent")} = p.${n("id")}
  from pg_temp.drive_sync_items item
  left join ${T} p
    on p.${n("drive")} = drive_sync_batch.drive
    and p.${n("source")} = ${source}
    and p.${n("externalId")} = item.parent_external_id
    and p.${n("kind")} = 'folder'${
      binColumn
        ? `
    and p.${n("deletedAt")} is null`
        : ""
    }
  where not item.removed
    and s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = ${source}
    and s.${n("externalId")} = item.external_id
    and s.${n("parent")} is distinct from p.${n("id")}
    and (p.${n("id")} is null or p.${n("id")} <> s.${n("id")});
  delete from ${T} s
  where s.${n("drive")} = drive_sync_batch.drive
    and s.${n("source")} = ${source}
    and s.${n("parent")} is null
    and s.${n("externalMetadata")} ->> 'parentExternalId' is not null
    and s.${n("externalMetadata")} ->> 'parentExternalId' <> drive_sync_batch.root_external_id
    and not ${fn("drive_node_held")}(s.${n("id")});${countDeleted()}${recordWrites}${pruneBlock}${cleanup}
  update ${C} c set
    ${c("syncCursor")} = coalesce(drive_sync_batch.cursor, c.${c("syncCursor")}),
    ${c("syncClaimedAt")} = null,
    ${c("lastSyncedAt")} = now(),
    ${c("lastSyncError")} = null${
      ctx.has("connections", "updatedAt")
        ? `,
    ${c("updatedAt")} = now()`
        : ""
    }
  where c.${c("id")} = v_connection.${c("id")};
  drop table pg_temp.drive_sync_items;
  return v_count;
end;
$$;
revoke execute on function ${fn("drive_sync_batch")}(uuid, jsonb, text, text, boolean, text) from public, anon, authenticated;
${serviceGrant(`${fn("drive_sync_batch")}(uuid, jsonb, text, text, boolean, text)`)}
`;
}
