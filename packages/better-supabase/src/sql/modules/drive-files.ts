import type { DriveKit } from "./drive-kit.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { labelTags, READ_ONLY_GUARD, UUID_TEXT } from "./drive-kit.ts";
import { liveShareLink } from "./share-links.ts";

/**
 * The approvals action a drive file's request uses:
 * `policies.<subjectType>.approve`.
 */
const APPROVE = "'approve'";

/** Files, revisions, the bin, stars and links: the drive-files module. */
export function driveFilesSql(kit: DriveKit): string {
  const {
    ctx,
    own,
    T,
    G,
    n,
    g,
    fn,
    read,
    driveColumn,
    readOnly,
    typeLit,
    attachments,
    A,
    a,
    versions,
    v,
    trash,
    ti,
    shareLinks,
    state,
    st,
    live,
    canRead,
    canWrite,
    canShare,
    notFound,
    forbidden,
    record,
    dataAudit,
    fileJson,
    nodeJson,
    json,
    withRole,
    orderBy,
    touch,
    siblings,
  } = kit;

  const tags = labelTags(own);

  const approvals =
    A !== undefined &&
    own.installed("approvals") &&
    own.of("approvals").mode !== "custom"
      ? own.of("approvals")
      : undefined;

  const tg = (column: string): string =>
    tags === undefined ? column : tags.col("taggings", column);

  const tt = (column: string): string =>
    tags === undefined ? column : tags.col("tags", column);

  const ar = (column: string): string =>
    approvals === undefined ? column : approvals.col("requests", column);

  const taggedNode = (alias: string, node: string): string =>
    tags === undefined
      ? "false"
      : `${alias}.${tg("subjectType")} = ${tags.cast("taggings", "subjectType", typeLit)} and ${alias}.${tg("subjectId")} = ${node}::text`;

  const labelJson =
    tags === undefined
      ? ""
      : `, 'labels', (select coalesce(jsonb_agg(jsonb_build_object('id', lt.${tt("id")}, 'name', lt.${tt("name")}, 'color', lt.${tt("color")}) order by ${tags.has("tags", "rank") ? `lt.${tt("rank")} collate "C", ` : ""}lt.${tt("name")}, lt.${tt("id")}), '[]'::jsonb)
      from ${tags.table("taggings")} lg join ${tags.table("tags")} lt on lt.${tt("id")} = lg.${tg("tag")}
      where ${taggedNode("lg", `($1).${n("id")}`)})`;

  const approvalJson =
    approvals === undefined
      ? ""
      : `, 'approval', (select jsonb_build_object('id', lr.${ar("id")}, 'status', lr.${ar("status")}, 'createdAt', lr.${ar("createdAt")}, 'decidedAt', lr.${ar("decidedAt")})
      from ${approvals.table("requests")} lr
      where lr.${ar("subjectType")} = ${typeLit} and lr.${ar("subjectId")} = ($1).${n("id")}::text and lr.${ar("action")} = ${APPROVE}
        and lr.${ar("payload")} ->> 'attachmentId' = ($1).${n("attachment")}::text
      order by lr.${ar("createdAt")} desc, lr.${ar("id")} limit 1)`;

  const purgeObjects =
    A === undefined
      ? "'[]'::jsonb"
      : `(select coalesce(jsonb_agg(jsonb_build_object('bucket', pa.${a("bucket")}, 'path', pa.${a("path")})), '[]'::jsonb) from ${A} pa where pa.${a("subjectType")} = ${typeLit} and pa.${a("subjectId")} = old.${n("id")}::text and pa.${a("uploadedAt")} is not null)`;

  const purgeCleanup = [
    A === undefined
      ? ""
      : `delete from ${A} pa where pa.${a("subjectType")} = ${typeLit} and pa.${a("subjectId")} = old.${n("id")}::text;`,
    `delete from ${G} pg where pg.${g("node")} = old.${n("id")};`,
    versions === undefined
      ? ""
      : `delete from ${versions.table("versions")} pv where pv.${v("subjectType")} = ${typeLit} and pv.${v("subjectId")} = old.${n("id")}::text;`,
    state === undefined
      ? ""
      : `delete from ${state.table("state")} ps where ps.${st("subjectType")} = ${typeLit} and ps.${st("subjectId")} = old.${n("id")}::text;`,
    tags === undefined
      ? ""
      : `delete from ${tags.table("taggings")} pt where ${taggedNode("pt", `old.${n("id")}`)};`,
  ]
    .filter((statement) => statement !== "")
    .join("\n  ");

  const fileFunctions =
    A === undefined || attachments === undefined
      ? ""
      : `
-- A new file and its pending attachment: upload to the attachment's
-- object_path, then call drive_commit. With conflict 'replace', a file of
-- the same name gets the upload as a new revision instead.
create or replace function ${fn("drive_create_file")}(tenant ${ctx.idType}, parent uuid, name text, mime_type text, size bigint, conflict text default null, fields jsonb default null, drive uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := ${fn("drive_clean_name")}(drive_create_file.name);
  v_conflict text := ${fn("drive_conflict")}(drive_create_file.conflict);
  v_drive uuid := drive_create_file.drive;
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  perform ${fn("drive_check_parent")}(drive_create_file.tenant, drive_create_file.parent, drive_create_file.drive);${
    driveColumn
      ? `
  if drive_create_file.parent is not null then
    select x.${n("drive")} into v_drive from ${T} x where x.${n("id")} = drive_create_file.parent;
  end if;`
      : ""
  }
  if v_conflict = 'replace' then
    perform ${fn("drive_lock_siblings")}(drive_create_file.tenant, v_drive, drive_create_file.parent);
    select * into v_node from ${T} x
    where ${siblings("x", "drive_create_file.tenant", "drive_create_file.parent", "v_drive")} and lower(x.${n("name")}) = lower(v_name);
    if found then
      if v_node.${n("kind")} <> 'file' then
        ${fail("DRIVE_NAME_CONFLICT", "a folder already has this name", "23505")}
      end if;
      return ${fn("drive_upload_revision")}(v_node.${n("id")}, drive_create_file.mime_type, drive_create_file.size);
    end if;
  end if;
  v_node := ${fn("drive_insert_node")}(drive_create_file.tenant, v_drive, drive_create_file.parent, 'file', v_name, v_conflict, drive_create_file.fields);
  return jsonb_build_object('node', ${json("v_node")}, 'attachment',
    ${attachments.fn("create_attachment")}(v_node.${n("tenant")}, v_node.${n("name")}, drive_create_file.mime_type, drive_create_file.size, ${typeLit}, v_node.${n("id")}::text));
end;
$$;
${userGrant(`${fn("drive_create_file")}(${ctx.idType}, uuid, text, text, bigint, text, jsonb, uuid)`)}

-- A pending attachment for a new revision of a file.
create or replace function ${fn("drive_upload_revision")}(node uuid, mime_type text, size bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  select * into v_node from ${T} x where x.${n("id")} = drive_upload_revision.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("change this file")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if v_node.${n("kind")} <> 'file' then
    ${fail("DRIVE_NOT_A_FILE", "a folder has no content", "22023")}
  end if;
  return jsonb_build_object('node', ${json("v_node")}, 'attachment',
    ${attachments.fn("create_attachment")}(v_node.${n("tenant")}, v_node.${n("name")}, drive_upload_revision.mime_type, drive_upload_revision.size, ${typeLit}, v_node.${n("id")}::text));
end;
$$;
${userGrant(`${fn("drive_upload_revision")}(uuid, text, bigint)`)}

-- Confirms the upload and makes it the file's content${versions === undefined ? "" : ", saved as a revision through the versions module"}.
create or replace function ${fn("drive_commit")}(node uuid, attachment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_file ${A}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_commit.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("change this file")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if not exists (
    select 1 from ${A} f where f.${a("id")} = drive_commit.attachment
      and f.${a("subjectType")} = ${typeLit} and f.${a("subjectId")} = v_node.${n("id")}::text
  ) then
    ${fail("DRIVE_ATTACHMENT_NOT_FOUND", "this upload does not belong to the file", "P0002")}
  end if;
  perform ${attachments.fn("confirm_attachment")}(drive_commit.attachment);
  select * into v_file from ${A} f where f.${a("id")} = drive_commit.attachment;
  if v_node.${n("attachment")} is distinct from v_file.${a("id")} then
    update ${T} x set ${n("attachment")} = v_file.${a("id")}${touch}
    where x.${n("id")} = v_node.${n("id")}
    returning * into v_node;${
      versions === undefined
        ? ""
        : `
    perform ${versions.fn("version_insert")}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text,
      jsonb_build_object('attachmentId', v_file.${a("id")}, 'name', v_file.${a("name")}, 'mimeType', v_file.${a("mimeType")}, 'size', v_file.${a("size")}),
      v_file.${a("bucket")} || '/' || v_file.${a("path")}, null, 'manual', false, auth.uid());`
    }
  end if;
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_commit")}(uuid, uuid)`)}

-- Whether the caller may run action (select, insert, update or delete) on
-- the object at path: files of a node need the node's grants. Objects of
-- other subjects pass, so the attachments policies decide.
create or replace function ${fn("drive_object_allowed")}(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when f.${a("subjectType")} is distinct from ${typeLit} then true
      when f.${a("subjectId")} !~ ${UUID_TEXT} then false
      when drive_object_allowed.action = 'select' then ${canRead(`f.${a("subjectId")}::uuid`)}
      else ${fn("drive_node_writable")}(f.${a("subjectId")}::uuid)
    end
    from ${A} f
    where f.${a("bucket")} = drive_object_allowed.bucket and f.${a("path")} = drive_object_allowed.path
  ), true)
$$;
${userGrant(`${fn("drive_object_allowed")}(text, text, text)`)}

create or replace function ${fn("drive_attachment_allowed")}(subject_type text, subject_id text, write boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when drive_attachment_allowed.subject_type is distinct from ${typeLit} then true
    when drive_attachment_allowed.subject_id !~ ${UUID_TEXT} then false
    when drive_attachment_allowed.write then ${fn("drive_node_writable")}(drive_attachment_allowed.subject_id::uuid)
    else ${canRead("drive_attachment_allowed.subject_id::uuid")}
  end
$$;
${userGrant(`${fn("drive_attachment_allowed")}(text, text, boolean)`)}

-- Restrictive policies: the attachments policies still apply, and a node's
-- files also need its grants.
${renderPolicy(makePolicy({ table: A, name: ctx.trigger("drive_attachments_read"), command: "select", roles: ["authenticated"], permissive: false, using: `${fn("drive_attachment_allowed")}(${a("subjectType")}, ${a("subjectId")}, false)` }), { drop: true, target: A })}
${renderPolicy(makePolicy({ table: A, name: ctx.trigger("drive_attachments_insert"), command: "insert", roles: ["authenticated"], permissive: false, check: `${fn("drive_attachment_allowed")}(${a("subjectType")}, ${a("subjectId")}, true)` }), { drop: true, target: A })}
${renderPolicy(makePolicy({ table: A, name: ctx.trigger("drive_attachments_delete"), command: "delete", roles: ["authenticated"], permissive: false, using: `${fn("drive_attachment_allowed")}(${a("subjectType")}, ${a("subjectId")}, true)` }), { drop: true, target: A })}
${renderPolicy(makePolicy({ table: "storage.objects", name: ctx.trigger("drive_objects_read"), command: "select", roles: ["authenticated"], permissive: false, using: `${fn("drive_object_allowed")}(bucket_id, name, 'select')` }), { drop: true, target: "storage.objects" })}
${renderPolicy(makePolicy({ table: "storage.objects", name: ctx.trigger("drive_objects_insert"), command: "insert", roles: ["authenticated"], permissive: false, check: `${fn("drive_object_allowed")}(bucket_id, name, 'insert')` }), { drop: true, target: "storage.objects" })}
${renderPolicy(makePolicy({ table: "storage.objects", name: ctx.trigger("drive_objects_update"), command: "update", roles: ["authenticated"], permissive: false, using: `${fn("drive_object_allowed")}(bucket_id, name, 'update')` }), { drop: true, target: "storage.objects" })}
${renderPolicy(makePolicy({ table: "storage.objects", name: ctx.trigger("drive_objects_delete"), command: "delete", roles: ["authenticated"], permissive: false, using: `${fn("drive_object_allowed")}(bucket_id, name, 'delete')` }), { drop: true, target: "storage.objects" })}

-- Attachments of nodes that are not the current content and not a saved
-- revision, older than a day so an upload in flight stays. Deletes their
-- records and returns the objects for the app to remove through Storage.
create or replace function ${fn("drive_prune")}(max_objects integer default 100)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with orphans as (
    select f.${a("id")} as id from ${A} f
    where f.${a("subjectType")} = ${typeLit}
      and f.${a("createdAt")} < now() - interval '1 day'
      and not exists (select 1 from ${T} x where x.${n("attachment")} = f.${a("id")})${
        versions === undefined
          ? ""
          : `
      and not exists (
        select 1 from ${versions.table("versions")} r
        where r.${v("subjectType")} = ${typeLit} and r.${v("subjectId")} = f.${a("subjectId")}
          and r.${v("content")} ->> 'attachmentId' = f.${a("id")}::text
      )`
      }
    order by f.${a("createdAt")}
    limit greatest(coalesce(drive_prune.max_objects, 100), 1)
  ), removed as (
    delete from ${A} f using orphans o where f.${a("id")} = o.id
    returning f.${a("bucket")} as bucket, f.${a("path")} as path, f.${a("uploadedAt")} as uploaded_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', r.bucket, 'path', r.path)) filter (where r.uploaded_at is not null), '[]'::jsonb) from removed r
$$;
${serviceGrant(`${fn("drive_prune")}(integer)`)}
`;

  const revisionFunctions =
    versions === undefined || A === undefined
      ? ""
      : `
create or replace function ${fn("drive_revisions")}(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_revisions.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.${v("id")}, 'number', r.${v("number")}, 'label', r.${v("label")}, 'source', r.${v("source")},
      'attachmentId', r.${v("content")} ->> 'attachmentId', 'name', r.${v("content")} ->> 'name',
      'mimeType', r.${v("content")} ->> 'mimeType', 'size', (r.${v("content")} ->> 'size')::bigint,
      'current', r.${v("content")} ->> 'attachmentId' = v_node.${n("attachment")}::text,
      'createdBy', r.${v("createdBy")}, 'createdAt', r.${v("createdAt")}
    ) order by r.${v("number")} desc), '[]'::jsonb)
    from ${versions.table("versions")} r
    where r.${v("subjectType")} = ${typeLit} and r.${v("subjectId")} = v_node.${n("id")}::text
  );
end;
$$;
${userGrant(`${fn("drive_revisions")}(uuid)`)}

-- Makes an earlier revision the content again, recorded as a new revision.
create or replace function ${fn("drive_restore_revision")}(node uuid, version uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_content jsonb;
  v_file ${A}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_restore_revision.node${live("x")} for update;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("change this file")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  select r.${v("content")} into v_content from ${versions.table("versions")} r
  where r.${v("id")} = drive_restore_revision.version
    and r.${v("subjectType")} = ${typeLit} and r.${v("subjectId")} = v_node.${n("id")}::text;
  if v_content is null or v_content ->> 'attachmentId' !~ ${UUID_TEXT} then
    ${fail("DRIVE_REVISION_NOT_FOUND", "revision not found", "P0002")}
  end if;
  select * into v_file from ${A} f where f.${a("id")} = (v_content ->> 'attachmentId')::uuid;
  if not found then
    ${fail("DRIVE_REVISION_NOT_FOUND", "the revision's file was pruned", "P0002")}
  end if;
  update ${T} x set ${n("attachment")} = v_file.${a("id")}${touch}
  where x.${n("id")} = v_node.${n("id")}
  returning * into v_node;
  perform ${versions.fn("version_insert")}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text,
    v_content, v_file.${a("bucket")} || '/' || v_file.${a("path")}, null, 'restore', false, auth.uid());
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_restore_revision")}(uuid, uuid)`)}
`;

  const binFunctions =
    trash === undefined
      ? ""
      : `
-- Moves a node and everything under it to the bin in one trash batch.
create or replace function ${fn("drive_trash")}(node uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_batch uuid := gen_random_uuid();
  v_count integer := 0;
  v_child record;
  v_id uuid;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_trash.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("move this item to the bin")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if ${fn("drive_node_held")}(v_node.${n("id")}) then
    ${fail("DRIVE_HELD", "this item is under a legal hold", "42501")}
  end if;
  for v_child in
    select s.node_id, s.depth from ${fn("drive_subtree")}(v_node.${n("id")}) s
    join ${T} x on x.${n("id")} = s.node_id
    where x.${n("deletedAt")} is null
    order by s.depth
  loop
    v_count := v_count + ${trash.fn("trash_cascade")}(v_node.${n("tenant")}, ${typeLit}, v_child.node_id::text, v_batch, v_child.depth, auth.uid());
  end loop;
  select i.${ti("id")} into v_id from ${trash.table("items")} i
  where i.${ti("subjectType")} = ${typeLit} and i.${ti("subjectId")} = v_node.${n("id")}::text;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$$;
${userGrant(`${fn("drive_trash")}(uuid)`)}

-- Restores a bin entry. A name taken in the meantime follows conflict; a
-- parent still in the bin has to be restored first.
create or replace function ${fn("drive_restore")}(item uuid, conflict text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_root ${trash.table("items")}%rowtype;
  v_node ${T}%rowtype;
  v_name text;
  v_count integer;
begin
  select r.* into v_root from ${trash.table("items")} i
  join ${trash.table("items")} r on r.${ti("batch")} = i.${ti("batch")} and r.${ti("depth")} = 0
  where i.${ti("id")} = drive_restore.item and r.${ti("subjectType")} = ${typeLit};
  if not found then
    ${notFound}
  end if;
  select * into v_node from ${T} x where x.${n("id")} = v_root.${ti("subjectId")}::uuid;
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("restore this item")}
  end if;
  if ${readOnly("v_node")} then
    ${fail("DRIVE_READ_ONLY", "this item mirrors an external account and is read-only", "42501")}
  end if;
  if v_node.${n("parent")} is not null and exists (
    select 1 from ${T} p where p.${n("id")} = v_node.${n("parent")} and p.${n("deletedAt")} is not null
  ) then
    ${fail("DRIVE_PARENT_TRASHED", "restore the folder this item was in first", "22023")}
  end if;
  v_name := ${fn("drive_free_name")}(v_node.${n("tenant")}, ${driveColumn ? `v_node.${n("drive")}` : "null"}, v_node.${n("parent")}, v_node.${n("name")}, v_node.${n("id")}, ${fn("drive_conflict")}(drive_restore.conflict));
  if v_name <> v_node.${n("name")} then
    update ${T} x set ${n("name")} = v_name where x.${n("id")} = v_node.${n("id")};
  end if;
  v_count := ${trash.fn("trash_restore_batch")}(v_root.${ti("batch")});
  delete from ${trash.table("items")} where ${ti("batch")} = v_root.${ti("batch")};
  select * into v_node from ${T} x where x.${n("id")} = v_node.${n("id")};
  return jsonb_build_object('id', v_root.${ti("id")}, 'batchId', v_root.${ti("batch")}, 'count', v_count, 'node', ${json("v_node")});
end;
$$;
${userGrant(`${fn("drive_restore")}(uuid, text)`)}

-- The bin: entries the caller may restore, newest first.
create or replace function ${fn("drive_bin")}(tenant ${ctx.idType}, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "drive_bin.tenant", read)}) then
    ${forbidden("read this organization's drive")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', b.item_id, 'batchId', b.batch_id, 'count', b.n, 'trashedBy', b.trashed_by, 'trashedAt', b.trashed_at, 'purgeAfter', b.purge_after, 'node', b.node) order by b.trashed_at desc, b.item_id), '[]'::jsonb)
    from (
      select i.${ti("id")} as item_id, i.${ti("batch")} as batch_id, i.${ti("trashedBy")} as trashed_by, i.${ti("trashedAt")} as trashed_at, i.${ti("purgeAfter")} as purge_after,
        (select count(*) from ${trash.table("items")} c where c.${ti("batch")} = i.${ti("batch")})::integer as n,
        ${json("x")} as node
      from ${trash.table("items")} i
      join ${T} x on x.${n("id")}::text = i.${ti("subjectId")}
      where i.${ti("tenant")} = drive_bin.tenant and i.${ti("subjectType")} = ${typeLit} and i.${ti("depth")} = 0
        and (drive_bin.before is null or i.${ti("trashedAt")} < drive_bin.before)
        and (${SERVICE_CALLER} or ${canWrite(`x.${n("id")}`)})
      order by i.${ti("trashedAt")} desc, i.${ti("id")}
      limit ${pageSize("drive_bin.page_size", 50, 200)}
    ) b
  );
end;
$$;
${userGrant(`${fn("drive_bin")}(${ctx.idType}, integer, timestamptz)`)}

-- Deletes a bin entry for good (the share role, or drive.manage).
create or replace function ${fn("drive_purge")}(item uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_root ${trash.table("items")}%rowtype;
begin
  select r.* into v_root from ${trash.table("items")} i
  join ${trash.table("items")} r on r.${ti("batch")} = i.${ti("batch")} and r.${ti("depth")} = 0
  where i.${ti("id")} = drive_purge.item and r.${ti("subjectType")} = ${typeLit};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_root.${ti("subjectId")}::uuid`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canShare(`v_root.${ti("subjectId")}::uuid`)}) then
    ${forbidden("delete this item for good")}
  end if;
  return ${trash.fn("trash_purge_batch")}(v_root.${ti("batch")});
end;
$$;
${userGrant(`${fn("drive_purge")}(uuid)`)}
`;

  const stateFunctions =
    state === undefined
      ? ""
      : `
create or replace function ${fn("drive_star")}(node uuid, starred boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not ${canRead("drive_star.node")} then
    ${notFound}
  end if;
  insert into ${state.table("state")} (${st("subjectType")}, ${st("subjectId")}, ${st("user")}, ${st("starredAt")})
  values (${typeLit}, drive_star.node::text, auth.uid(), case when drive_star.starred then now() end)
  on conflict (${st("subjectType")}, ${st("subjectId")}, ${st("user")})
  do update set ${st("starredAt")} = case when drive_star.starred then coalesce(${state.table("state")}.${st("starredAt")}, now()) end;
  return drive_star.starred;
end;
$$;
${userGrant(`${fn("drive_star")}(uuid, boolean)`)}

create or replace function ${fn("drive_open")}(node uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_open.node${live("x")};
  if not found or auth.uid() is null or not ${canRead(`v_node.${n("id")}`)} then
    ${notFound}
  end if;
  insert into ${state.table("state")} (${st("subjectType")}, ${st("subjectId")}, ${st("user")}, ${st("lastOpenedAt")})
  values (${typeLit}, v_node.${n("id")}::text, auth.uid(), now())
  on conflict (${st("subjectType")}, ${st("subjectId")}, ${st("user")})
  do update set ${st("lastOpenedAt")} = now();
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_open")}(uuid)`)}

-- The caller's starred nodes (recent false) or recently opened ones (true).
create or replace function ${fn("drive_marked")}(tenant ${ctx.idType}, recent boolean default false, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(t.node order by t.marked_at desc), '[]'::jsonb) from (
    select ${withRole("x")} || jsonb_build_object('starredAt', s.${st("starredAt")}, 'openedAt', s.${st("lastOpenedAt")}) as node,
      case when drive_marked.recent then s.${st("lastOpenedAt")} else s.${st("starredAt")} end as marked_at
    from ${state.table("state")} s
    join ${T} x on x.${n("id")}::text = s.${st("subjectId")}
    where s.${st("subjectType")} = ${typeLit} and s.${st("user")} = auth.uid()
      and x.${n("tenant")} = drive_marked.tenant${live("x")}
      and case when drive_marked.recent then s.${st("lastOpenedAt")} else s.${st("starredAt")} end is not null
      and ${canRead(`x.${n("id")}`)}
    order by marked_at desc
    limit ${pageSize("drive_marked.page_size", 50, 200)}
  ) t
$$;
${userGrant(`${fn("drive_marked")}(${ctx.idType}, boolean, integer)`)}
`;

  const linkFunction =
    shareLinks === undefined
      ? ""
      : `
-- What a share link on a node opens: the node and, for a folder, its
-- children. node picks an item under the linked folder. For a file, file
-- carries the object for the server to sign a download URL with.
create or replace function ${fn("drive_link")}(token text, node uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link_id uuid;
  v_role text;
  v_root text;
  v_expires timestamptz;
  v_tenant text;
  v_node ${T}%rowtype;
begin
  select l.${shareLinks.col("links", "id")}, l.${shareLinks.col("links", "role")}, l.${shareLinks.col("links", "subjectId")}, l.${shareLinks.col("links", "expiresAt")}, l.${shareLinks.col("links", "tenant")}::text
    into v_link_id, v_role, v_root, v_expires, v_tenant
  from ${shareLinks.table("links")} l
  where ${liveShareLink(shareLinks, "l", "drive_link.token", typeLit)};
  if v_link_id is null or v_root !~ ${UUID_TEXT} then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not exist or has expired", "P0002")}
  end if;
  select * into v_node from ${T} x where x.${n("id")} = coalesce(drive_link.node, v_root::uuid)
    and x.${n("tenant")}::text = v_tenant${live("x")};
  if not found or not (v_root::uuid = any (${fn("drive_ancestors")}(v_node.${n("id")}))) then
    ${fail("DRIVE_LINK_NOT_FOUND", "this link does not open that item", "P0002")}
  end if;
  return jsonb_build_object(
    'link', jsonb_build_object('id', v_link_id, 'role', v_role, 'nodeId', v_root::uuid, 'expiresAt', v_expires),
    'node', ${json("v_node")},
    'children', case when v_node.${n("kind")} = 'folder' then (
      select coalesce(jsonb_agg(${json("c.r")} order by ${orderBy("(c.r)")}), '[]'::jsonb)
      from (select y as r from ${T} y where y.${n("parent")} = v_node.${n("id")}${live("y")} order by ${orderBy("y")} limit 500) c
    ) end${
      A === undefined
        ? ""
        : `,
    'object', (select jsonb_build_object('bucket', f.${a("bucket")}, 'path', f.${a("path")}, 'mimeType', f.${a("mimeType")}, 'status', f.${a("status")})
      from ${A} f where f.${a("id")} = v_node.${n("attachment")})`
    }
  );
end;
$$;
revoke all on function ${fn("drive_link")}(text, uuid) from public, anon, authenticated;
grant execute on function ${fn("drive_link")}(text, uuid) to anon, authenticated, service_role;
`;

  const labelFunctions =
    tags === undefined
      ? ""
      : `
-- Puts a tenant tag on a node as a label, or takes it off (applied false),
-- for an editor of the node; tags' own permission and kind checks apply.
create or replace function ${fn("drive_label")}(node uuid, tag uuid, applied boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  select * into v_node from ${T} x where x.${n("id")} = drive_label.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("label this item")}
  end if;
  if coalesce(drive_label.applied, true) then
    perform ${tags.fn("tag")}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text, drive_label.tag);
  else
    perform ${tags.fn("untag")}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text, drive_label.tag);
  end if;
  return ${withRole("v_node")};
end;
$$;
${userGrant(`${fn("drive_label")}(uuid, uuid, boolean)`)}

-- The nodes in a tenant that carry a label and the caller can read.
create or replace function ${fn("drive_labeled")}(tenant ${ctx.idType}, tag uuid, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(t.node order by t.ord), '[]'::jsonb) from (
    select ${withRole("x")} as node, row_number() over (order by ${orderBy("x")}) as ord
    from ${T} x
    where x.${n("tenant")} = drive_labeled.tenant${live("x")}
      and exists (select 1 from ${tags.table("taggings")} lg where ${taggedNode("lg", `x.${n("id")}`)} and lg.${tg("tag")} = drive_labeled.tag)
      and (${SERVICE_CALLER} or ${canRead(`x.${n("id")}`)})
    order by ${orderBy("x")}
    limit ${pageSize("drive_labeled.page_size", 50, 200)}
  ) t
$$;
${userGrant(`${fn("drive_labeled")}(${ctx.idType}, uuid, integer)`)}
`;

  const approvalFunctions =
    approvals === undefined || A === undefined
      ? ""
      : `
-- Asks for approval of one stored version of a file: attachment, or the
-- current one. The request follows those bytes, so a later upload doesn't
-- inherit it and restoring the version brings it back.
create or replace function ${fn("drive_request_approval")}(node uuid, attachment uuid default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_file ${A}%rowtype;
  v_revision integer;
begin
  ${READ_ONLY_GUARD}
  select * into v_node from ${T} x where x.${n("id")} = drive_request_approval.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite(`v_node.${n("id")}`)}) then
    ${forbidden("ask for approval of this file")}
  end if;
  if v_node.${n("kind")} <> 'file' then
    ${fail("DRIVE_NOT_A_FILE", "only a file can be approved", "22023")}
  end if;
  select * into v_file from ${A} f
  where f.${a("id")} = coalesce(drive_request_approval.attachment, v_node.${n("attachment")})
    and f.${a("subjectType")} = ${typeLit} and f.${a("subjectId")} = v_node.${n("id")}::text
    and f.${a("uploadedAt")} is not null;
  if not found then
    ${fail("DRIVE_ATTACHMENT_NOT_FOUND", "that version of the file was not found", "P0002")}
  end if;${
    versions === undefined
      ? ""
      : `
  select r.${v("number")} into v_revision from ${versions.table("versions")} r
  where r.${v("subjectType")} = ${typeLit} and r.${v("subjectId")} = v_node.${n("id")}::text
    and r.${v("content")} ->> 'attachmentId' = v_file.${a("id")}::text
  order by r.${v("number")} limit 1;`
  }
  return ${approvals.fn("request_approval")}(v_node.${n("tenant")}, ${typeLit}, v_node.${n("id")}::text, ${APPROVE},
    drive_request_approval.reason, jsonb_build_object('attachmentId', v_file.${a("id")}, 'revision', v_revision, 'name', v_file.${a("name")}))
    || jsonb_build_object('attachmentId', v_file.${a("id")}, 'revision', v_revision, 'current', v_file.${a("id")} = v_node.${n("attachment")});
end;
$$;
${userGrant(`${fn("drive_request_approval")}(uuid, uuid, text)`)}

-- A file's approval requests, newest first, each with the version it is for
-- and whether that version is the current one. Approvals' read rules apply.
create or replace function ${fn("drive_approvals")}(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
begin
  select * into v_node from ${T} x where x.${n("id")} = drive_approvals.node${live("x")};
  if not found or not (${SERVICE_CALLER} or ${canRead(`v_node.${n("id")}`)}) then
    ${notFound}
  end if;
  return (
    select coalesce(jsonb_agg(r.value || jsonb_build_object(
      'attachmentId', r.value -> 'payload' ->> 'attachmentId',
      'revision', (r.value -> 'payload' ->> 'revision')::integer,
      'current', r.value -> 'payload' ->> 'attachmentId' = v_node.${n("attachment")}::text
    ) order by r.ordinality), '[]'::jsonb)
    from jsonb_array_elements(${approvals.fn("list_approvals")}(v_node.${n("tenant")}, null, false, ${typeLit}, v_node.${n("id")}::text, 200, null)) with ordinality r
    where r.value ->> 'action' = ${APPROVE}
  );
end;
$$;
${userGrant(`${fn("drive_approvals")}(uuid)`)}
`;

  const attachmentKey =
    ctx.owns("nodes") && A !== undefined
      ? `
alter table ${T} drop constraint if exists bsb_drive_nodes_attachment;
alter table ${T} add constraint bsb_drive_nodes_attachment foreign key (${n("attachment")}) references ${A} (${a("id")}) on delete set null;
`
      : "";

  const fileNodeJson =
    A === undefined
      ? ""
      : `
create or replace function ${fn("drive_node_json")}(node ${T})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${nodeJson(`${fileJson}${labelJson}${approvalJson}`)}
$$;
revoke execute on function ${fn("drive_node_json")}(${T}) from public, anon, authenticated;
`;

  const late = `${schemaPreamble(own)}
${attachmentKey}${fileNodeJson}
-- Before a node is deleted for good, its stored objects go into
-- drive.node_purged for the app to remove through Storage; after, its
-- grants, attachments${versions === undefined ? "" : ", revisions"}${state === undefined ? "" : " and starred state"} go too.
create or replace function ${fn("drive_node_purging")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_objects jsonb := ${purgeObjects};
begin
  ${record("drive.node_purged", "old", ", 'objects', v_objects", dataAudit("old", "deleted for good"))}
  return old;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_purging")} on ${T};
create trigger ${ctx.trigger("drive_node_purging")}
  before delete on ${T}
  for each row execute function ${fn("drive_node_purging")}();

create or replace function ${fn("drive_node_purged")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${purgeCleanup}
  return null;
end;
$$;
drop trigger if exists ${ctx.trigger("drive_node_purged")} on ${T};
create trigger ${ctx.trigger("drive_node_purged")}
  after delete on ${T}
  for each row execute function ${fn("drive_node_purged")}();
${fileFunctions}${revisionFunctions}${binFunctions}${stateFunctions}${linkFunction}${labelFunctions}${approvalFunctions}`;

  return late;
}
