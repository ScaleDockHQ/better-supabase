import type { DriveKit } from "./drive-kit.ts";

import {
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { READ_ONLY_GUARD, UUID_TEXT } from "./drive-kit.ts";
import { liveShareLink } from "./share-links.ts";

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
create or replace function ${fn("drive_create_file")}(tenant ${ctx.idType}, parent uuid, name text, mime_type text, size bigint, conflict text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := ${fn("drive_clean_name")}(drive_create_file.name);
  v_conflict text := ${fn("drive_conflict")}(drive_create_file.conflict);
  v_node ${T}%rowtype;
begin
  ${READ_ONLY_GUARD}
  perform ${fn("drive_check_parent")}(drive_create_file.tenant, drive_create_file.parent);
  if v_conflict = 'replace' then
    perform ${fn("drive_lock_siblings")}(drive_create_file.tenant, drive_create_file.parent);
    select * into v_node from ${T} x
    where ${siblings("x", "drive_create_file.tenant", "drive_create_file.parent")} and lower(x.${n("name")}) = lower(v_name);
    if found then
      if v_node.${n("kind")} <> 'file' then
        ${fail("DRIVE_NAME_CONFLICT", "a folder already has this name", "23505")}
      end if;
      return ${fn("drive_upload_revision")}(v_node.${n("id")}, drive_create_file.mime_type, drive_create_file.size);
    end if;
  end if;
  v_node := ${fn("drive_insert_node")}(drive_create_file.tenant, drive_create_file.parent, 'file', v_name, v_conflict, drive_create_file.fields);
  return jsonb_build_object('node', ${json("v_node")}, 'attachment',
    ${attachments.fn("create_attachment")}(v_node.${n("tenant")}, v_node.${n("name")}, drive_create_file.mime_type, drive_create_file.size, ${typeLit}, v_node.${n("id")}::text));
end;
$$;
${userGrant(`${fn("drive_create_file")}(${ctx.idType}, uuid, text, text, bigint, text, jsonb)`)}

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
      else ${canWrite(`f.${a("subjectId")}::uuid`)}
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
    when drive_attachment_allowed.write then ${canWrite("drive_attachment_allowed.subject_id::uuid")}
    else ${canRead("drive_attachment_allowed.subject_id::uuid")}
  end
$$;
${userGrant(`${fn("drive_attachment_allowed")}(text, text, boolean)`)}

-- Restrictive policies: the attachments policies still apply, and a node's
-- files also need its grants.
drop policy if exists ${ctx.trigger("drive_attachments_read")} on ${A};
create policy ${ctx.trigger("drive_attachments_read")} on ${A} as restrictive for select to authenticated
  using (${fn("drive_attachment_allowed")}(${a("subjectType")}, ${a("subjectId")}, false));
drop policy if exists ${ctx.trigger("drive_attachments_insert")} on ${A};
create policy ${ctx.trigger("drive_attachments_insert")} on ${A} as restrictive for insert to authenticated
  with check (${fn("drive_attachment_allowed")}(${a("subjectType")}, ${a("subjectId")}, true));
drop policy if exists ${ctx.trigger("drive_attachments_delete")} on ${A};
create policy ${ctx.trigger("drive_attachments_delete")} on ${A} as restrictive for delete to authenticated
  using (${fn("drive_attachment_allowed")}(${a("subjectType")}, ${a("subjectId")}, true));
drop policy if exists ${ctx.trigger("drive_objects_read")} on storage.objects;
create policy ${ctx.trigger("drive_objects_read")} on storage.objects as restrictive for select to authenticated
  using (${fn("drive_object_allowed")}(bucket_id, name, 'select'));
drop policy if exists ${ctx.trigger("drive_objects_insert")} on storage.objects;
create policy ${ctx.trigger("drive_objects_insert")} on storage.objects as restrictive for insert to authenticated
  with check (${fn("drive_object_allowed")}(bucket_id, name, 'insert'));
drop policy if exists ${ctx.trigger("drive_objects_update")} on storage.objects;
create policy ${ctx.trigger("drive_objects_update")} on storage.objects as restrictive for update to authenticated
  using (${fn("drive_object_allowed")}(bucket_id, name, 'update'));
drop policy if exists ${ctx.trigger("drive_objects_delete")} on storage.objects;
create policy ${ctx.trigger("drive_objects_delete")} on storage.objects as restrictive for delete to authenticated
  using (${fn("drive_object_allowed")}(bucket_id, name, 'delete'));

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
  if v_node.${n("parent")} is not null and exists (
    select 1 from ${T} p where p.${n("id")} = v_node.${n("parent")} and p.${n("deletedAt")} is not null
  ) then
    ${fail("DRIVE_PARENT_TRASHED", "restore the folder this item was in first", "22023")}
  end if;
  v_name := ${fn("drive_free_name")}(v_node.${n("tenant")}, v_node.${n("parent")}, v_node.${n("name")}, v_node.${n("id")}, ${fn("drive_conflict")}(drive_restore.conflict));
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

  const attachmentKey =
    ctx.manages && A !== undefined
      ? `
alter table ${T} drop constraint if exists bs_drive_nodes_attachment;
alter table ${T} add constraint bs_drive_nodes_attachment foreign key (${n("attachment")}) references ${A} (${a("id")}) on delete set null;
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
  select ${nodeJson(fileJson)}
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
${fileFunctions}${revisionFunctions}${binFunctions}${stateFunctions}${linkFunction}`;

  return late;
}
