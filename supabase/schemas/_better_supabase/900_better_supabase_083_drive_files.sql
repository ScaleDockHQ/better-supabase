-- better-supabase module: drive-files
-- @bsb-block drive-files@1 managed
-- @bsb-hash sha256:de068e28dafeb4c4ebda982a5786203e43a6b01ce70844a1d0649e3c0c5b4d1f
-- The part of the drive module that needs attachments, versions, trash and share-links: file uploads and revisions, storage policies, the bin, starred and recent items, folder share links and the purge event. Installed with drive.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

alter table "better_supabase"."drive_nodes" drop constraint if exists bsb_drive_nodes_attachment;
alter table "better_supabase"."drive_nodes" add constraint bsb_drive_nodes_attachment foreign key ("attachment_id") references "better_supabase"."attachments" ("id") on delete set null;

create or replace function "better_supabase"."drive_node_json"(node "better_supabase"."drive_nodes")
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."tenant_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', ($1)."rank", 'source', ($1)."source", 'externalId', ($1)."external_id", 'externalMetadata', ($1)."external_metadata", 'legalHoldUntil', ($1)."legal_hold_until", 'lockedBy', case when ($1)."locked_until" > now() then ($1)."locked_by" end, 'lockedUntil', case when ($1)."locked_until" > now() then ($1)."locked_until" end, 'lockNote', case when ($1)."locked_until" > now() then ($1)."lock_note" end, 'downloadBlocked', ($1)."download_blocked", 'previewPages', ($1)."preview_pages", 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', ($1)."deleted_at", 'attachmentId', ($1)."attachment_id", 'file', (select jsonb_build_object('mimeType', fa."mime_type", 'size', fa."size", 'status', fa."status", 'uploadedAt', fa."uploaded_at") from "better_supabase"."attachments" fa where fa."id" = ($1)."attachment_id"), 'labels', (select coalesce(jsonb_agg(jsonb_build_object('id', lt."id", 'name', lt."name", 'color', lt."color") order by lt."rank" collate "C", lt."name", lt."id"), '[]'::jsonb)
      from "better_supabase"."taggings" lg join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
      where lg."subject_type" = 'drive_node' and lg."subject_id" = ($1)."id"::text), 'approval', (select jsonb_build_object('id', lr."id", 'status', lr."status", 'createdAt', lr."created_at", 'decidedAt', lr."decided_at")
      from "better_supabase"."approval_requests" lr
      where lr."subject_type" = 'drive_node' and lr."subject_id" = ($1)."id"::text and lr."action" = 'approve'
        and lr."payload" ->> 'attachmentId' = ($1)."attachment_id"::text
      order by lr."created_at" desc, lr."id" limit 1))
$$;
revoke execute on function "better_supabase"."drive_node_json"("better_supabase"."drive_nodes") from public, anon, authenticated;

-- Before a node is deleted for good, its stored objects go into
-- drive.node_purged for the app to remove through Storage; after, its
-- grants, attachments, revisions and starred state go too.
create or replace function "better_supabase"."drive_node_purging"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_objects jsonb := (select coalesce(jsonb_agg(jsonb_build_object('bucket', pa."bucket", 'path', pa."object_path")), '[]'::jsonb) from "better_supabase"."attachments" pa where pa."subject_type" = 'drive_node' and pa."subject_id" = old."id"::text and pa."uploaded_at" is not null);
begin
  perform "better_supabase".emit_event('drive.node_purged', jsonb_build_object('organizationId', old."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects), 'drive-nodes/' || old."id"::text, (old."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive.node_purged',
    category => 'data',
    target_type => 'drive_node',
    record_id => old."id"::text,
    target_label => old."name",
    summary => 'deleted for good',
    tenant => (old."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', old."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects)
  );
  return old;
end;
$$;
drop trigger if exists "bsb_drive_node_purging" on "better_supabase"."drive_nodes";
create trigger "bsb_drive_node_purging"
  before delete on "better_supabase"."drive_nodes"
  for each row execute function "better_supabase"."drive_node_purging"();

create or replace function "better_supabase"."drive_node_purged"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."attachments" pa where pa."subject_type" = 'drive_node' and pa."subject_id" = old."id"::text;
  delete from "better_supabase"."drive_grants" pg where pg."node_id" = old."id";
  delete from "better_supabase"."versions" pv where pv."subject_type" = 'drive_node' and pv."subject_id" = old."id"::text;
  delete from "better_supabase"."subject_user_state" ps where ps."subject_type" = 'drive_node' and ps."subject_id" = old."id"::text;
  delete from "better_supabase"."taggings" pt where pt."subject_type" = 'drive_node' and pt."subject_id" = old."id"::text;
  return null;
end;
$$;
drop trigger if exists "bsb_drive_node_purged" on "better_supabase"."drive_nodes";
create trigger "bsb_drive_node_purged"
  after delete on "better_supabase"."drive_nodes"
  for each row execute function "better_supabase"."drive_node_purged"();

-- A new file and its pending attachment: upload to the attachment's
-- object_path, then call drive_commit. With conflict 'replace', a file of
-- the same name gets the upload as a new revision instead.
-- A caller with only options.uploadRole (contributor) on the folder gets
-- { id, attachment } and no node: the file takes a free name, and
-- they can't read it once committed.
create or replace function "better_supabase"."drive_create_file"(tenant uuid, parent uuid, name text, mime_type text, size bigint, conflict text default null, fields jsonb default null, drive uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_name text := "better_supabase"."drive_clean_name"(drive_create_file.name);
  v_conflict text := "better_supabase"."drive_conflict"(drive_create_file.conflict);
  v_drive uuid := drive_create_file.drive;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and drive_create_file.parent is not null
    and exists (select 1 from "better_supabase"."drive_nodes" x where x."id" = drive_create_file.parent and x."tenant_id" = drive_create_file.tenant and x."deleted_at" is null)
    and not "better_supabase"."drive_can"(drive_create_file.parent, 'viewer') and "better_supabase"."drive_can_upload"(drive_create_file.parent) then
    v_node := "better_supabase"."drive_insert_node"(drive_create_file.tenant, null, drive_create_file.parent, 'file', v_name, 'rename', drive_create_file.fields);
    v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_create_file.mime_type, drive_create_file.size, 'drive_node', v_node."id"::text);
    return jsonb_build_object('id', v_node."id", 'attachment', v_attachment);
  end if;
  perform "better_supabase"."drive_check_parent"(drive_create_file.tenant, drive_create_file.parent, drive_create_file.drive);
  if v_conflict = 'replace' then
    perform "better_supabase"."drive_lock_siblings"(drive_create_file.tenant, v_drive, drive_create_file.parent);
    select * into v_node from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_create_file.tenant and x."parent_id" is not distinct from drive_create_file.parent and x."deleted_at" is null and lower(x."name") = lower(v_name);
    if found then
      if v_node."kind" <> 'file' then
        raise exception 'a folder already has this name' using errcode = '23505', hint = 'DRIVE_NAME_CONFLICT';
      end if;
      return "better_supabase"."drive_upload_revision"(v_node."id", drive_create_file.mime_type, drive_create_file.size);
    end if;
  end if;
  v_node := "better_supabase"."drive_insert_node"(drive_create_file.tenant, v_drive, drive_create_file.parent, 'file', v_name, v_conflict, drive_create_file.fields);
  return jsonb_build_object('node', "better_supabase"."drive_node_json"(v_node), 'attachment',
    "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_create_file.mime_type, drive_create_file.size, 'drive_node', v_node."id"::text));
end;
$$;
revoke execute on function "better_supabase"."drive_create_file"(uuid, uuid, text, text, bigint, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."drive_create_file"(uuid, uuid, text, text, bigint, text, jsonb, uuid) to authenticated, service_role;

-- A pending attachment for a new revision of a file.
create or replace function "better_supabase"."drive_upload_revision"(node uuid, mime_type text, size bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_upload_revision.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'a folder has no content' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_upload_revision.mime_type, drive_upload_revision.size, 'drive_node', v_node."id"::text);
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    return jsonb_build_object('id', v_node."id", 'attachment', v_attachment);
  end if;
  return jsonb_build_object('node', "better_supabase"."drive_node_json"(v_node), 'attachment', v_attachment);
end;
$$;
revoke execute on function "better_supabase"."drive_upload_revision"(uuid, text, bigint) from public, anon;
grant execute on function "better_supabase"."drive_upload_revision"(uuid, text, bigint) to authenticated, service_role;

-- Confirms the upload and makes it the file's content, saved as a revision through the versions module.
create or replace function "better_supabase"."drive_commit"(node uuid, attachment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_commit.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if not exists (
    select 1 from "better_supabase"."attachments" f where f."id" = drive_commit.attachment
      and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
  ) then
    raise exception 'this upload does not belong to the file' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  perform "better_supabase"."confirm_attachment"(drive_commit.attachment);
  select * into v_file from "better_supabase"."attachments" f where f."id" = drive_commit.attachment;
  if v_node."attachment_id" is distinct from v_file."id" then
    update "better_supabase"."drive_nodes" x set "attachment_id" = v_file."id", "preview_pages" = null, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", null, 'manual', false, auth.uid());
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    return jsonb_build_object('id', v_node."id", 'attachmentId', v_file."id", 'committed', true);
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_commit"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."drive_commit"(uuid, uuid) to authenticated, service_role;

-- Whether the caller may run action (select, insert, update or delete) on
-- the object at path: files of a node need the node's grants, and reading an
-- original needs drive_can_download. Previews under _previews/ need read
-- access, and only the service role writes them. Objects of other subjects pass, so
-- the attachments policies decide.
create or replace function "better_supabase"."drive_object_allowed"(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when drive_object_allowed.path like '_previews/%' then
    drive_object_allowed.action = 'select'
      and split_part(drive_object_allowed.path, '/', 3) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and "better_supabase"."drive_can"(split_part(drive_object_allowed.path, '/', 3)::uuid, 'viewer')
  else coalesce((
    select case
      when f."subject_type" is distinct from 'drive_node' then true
      when f."subject_id" !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
      when drive_object_allowed.action = 'select' then "better_supabase"."drive_can_download"(f."subject_id"::uuid)
      else "better_supabase"."drive_node_writable"(f."subject_id"::uuid) or "better_supabase"."drive_uploaded_own"(f."subject_id"::uuid)
    end
    from "better_supabase"."attachments" f
    where f."bucket" = drive_object_allowed.bucket and f."object_path" = drive_object_allowed.path
  ), true) end
$$;
revoke execute on function "better_supabase"."drive_object_allowed"(text, text, text) from public, anon;
grant execute on function "better_supabase"."drive_object_allowed"(text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."drive_attachment_allowed"(subject_type text, subject_id text, write boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when drive_attachment_allowed.subject_type is distinct from 'drive_node' then true
    when drive_attachment_allowed.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
    when drive_attachment_allowed.write then "better_supabase"."drive_node_writable"(drive_attachment_allowed.subject_id::uuid) or "better_supabase"."drive_uploaded_own"(drive_attachment_allowed.subject_id::uuid)
    else "better_supabase"."drive_can"(drive_attachment_allowed.subject_id::uuid, 'viewer')
  end
$$;
revoke execute on function "better_supabase"."drive_attachment_allowed"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."drive_attachment_allowed"(text, text, boolean) to authenticated, service_role;

-- Restrictive policies: the attachments policies still apply, and a node's
-- files also need its grants.
drop policy if exists bsb_drive_attachments_read on "better_supabase"."attachments";
create policy bsb_drive_attachments_read on "better_supabase"."attachments" as restrictive
  for select to authenticated
  using ("better_supabase"."drive_attachment_allowed"("subject_type", "subject_id", false));
drop policy if exists bsb_drive_attachments_insert on "better_supabase"."attachments";
create policy bsb_drive_attachments_insert on "better_supabase"."attachments" as restrictive
  for insert to authenticated
  with check (("better_supabase"."drive_attachment_allowed"("subject_type", "subject_id", true)) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_drive_attachments_delete on "better_supabase"."attachments";
create policy bsb_drive_attachments_delete on "better_supabase"."attachments" as restrictive
  for delete to authenticated
  using (("better_supabase"."drive_attachment_allowed"("subject_type", "subject_id", true)) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_drive_objects_read on storage.objects;
create policy bsb_drive_objects_read on storage.objects as restrictive
  for select to authenticated
  using ("better_supabase"."drive_object_allowed"(bucket_id, name, 'select'));
drop policy if exists bsb_drive_previews_read on storage.objects;
create policy bsb_drive_previews_read on storage.objects
  for select to authenticated
  using (name like '_previews/%' and "better_supabase"."drive_object_allowed"(bucket_id, name, 'select'));
drop policy if exists bsb_drive_objects_insert on storage.objects;
create policy bsb_drive_objects_insert on storage.objects as restrictive
  for insert to authenticated
  with check (("better_supabase"."drive_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_drive_objects_update on storage.objects;
create policy bsb_drive_objects_update on storage.objects as restrictive
  for update to authenticated
  using (("better_supabase"."drive_object_allowed"(bucket_id, name, 'update')) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_drive_objects_delete on storage.objects;
create policy bsb_drive_objects_delete on storage.objects as restrictive
  for delete to authenticated
  using (("better_supabase"."drive_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- Attachments of nodes that are not the current content and not a saved
-- revision, older than a day so an upload in flight stays. Deletes their
-- records and returns the objects for the app to remove through Storage.
create or replace function "better_supabase"."drive_prune"(max_objects integer default 100)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with orphans as (
    select f."id" as id from "better_supabase"."attachments" f
    where f."subject_type" = 'drive_node'
      and f."created_at" < now() - interval '1 day'
      and not exists (select 1 from "better_supabase"."drive_nodes" x where x."attachment_id" = f."id")
      and not exists (
        select 1 from "better_supabase"."versions" r
        where r."subject_type" = 'drive_node' and r."subject_id" = f."subject_id"
          and r."content" ->> 'attachmentId' = f."id"::text
      )
    order by f."created_at"
    limit greatest(coalesce(drive_prune.max_objects, 100), 1)
  ), removed as (
    delete from "better_supabase"."attachments" f using orphans o where f."id" = o.id
    returning f."bucket" as bucket, f."object_path" as path, f."uploaded_at" as uploaded_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', r.bucket, 'path', r.path)) filter (where r.uploaded_at is not null), '[]'::jsonb) from removed r
$$;
revoke execute on function "better_supabase"."drive_prune"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_prune"(integer) to service_role;

-- The rendered pages of a file's current content: { attachmentId, bucket,
-- pages, prefix, paths }, with no pages until the preview renderer has run.
create or replace function "better_supabase"."drive_preview_json"(node "better_supabase"."drive_nodes")
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when ($1)."attachment_id" is null then null else jsonb_build_object(
    'attachmentId', ($1)."attachment_id",
    'bucket', (select f."bucket" from "better_supabase"."attachments" f where f."id" = ($1)."attachment_id"),
    'pages', coalesce(($1)."preview_pages", 0),
    'prefix', '_previews/' || ($1)."tenant_id"::text || '/' || ($1)."id"::text || '/' || ($1)."attachment_id"::text,
    'paths', coalesce((
      select jsonb_agg('_previews/' || ($1)."tenant_id"::text || '/' || ($1)."id"::text || '/' || ($1)."attachment_id"::text || '/' || p::text order by p)
      from generate_series(1, coalesce(($1)."preview_pages", 0)) p
    ), '[]'::jsonb)
  ) end
$$;
revoke execute on function "better_supabase"."drive_preview_json"("better_supabase"."drive_nodes") from public, anon, authenticated;

-- A file's previews for a reader. Previews need read access only, so a
-- download block leaves them visible.
create or replace function "better_supabase"."drive_previews"(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_previews.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'a folder has no previews' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  return "better_supabase"."drive_preview_json"(v_node);
end;
$$;
revoke execute on function "better_supabase"."drive_previews"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_previews"(uuid) to authenticated, service_role;

-- Service role: records how many pages the renderer stored for attachment
-- under _previews/<tenant>/<node>/<attachment>/<page>. A file whose content
-- changed since keeps no previews, so stale pages never show.
create or replace function "better_supabase"."drive_set_previews"(node uuid, attachment uuid, pages integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if drive_set_previews.pages is null or drive_set_previews.pages < 0 then
    raise exception 'pages must be zero or more' using errcode = '22023', hint = 'DRIVE_PREVIEWS_INVALID';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_set_previews.node for update;
  if not found then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."attachment_id" is distinct from drive_set_previews.attachment then
    return "better_supabase"."drive_preview_json"(v_node);
  end if;
  update "better_supabase"."drive_nodes" x set "preview_pages" = drive_set_previews.pages
  where x."id" = v_node."id"
  returning * into v_node;
  return "better_supabase"."drive_preview_json"(v_node);
end;
$$;
revoke execute on function "better_supabase"."drive_set_previews"(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_set_previews"(uuid, uuid, integer) to service_role;

create or replace function "better_supabase"."drive_revisions"(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_revisions.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id", 'number', r."number", 'label', r."label", 'source', r."source",
      'attachmentId', r."content" ->> 'attachmentId', 'name', r."content" ->> 'name',
      'mimeType', r."content" ->> 'mimeType', 'size', (r."content" ->> 'size')::bigint,
      'current', r."content" ->> 'attachmentId' = v_node."attachment_id"::text,
      'createdBy', r."created_by", 'createdAt', r."created_at"
    ) order by r."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" r
    where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
  );
end;
$$;
revoke execute on function "better_supabase"."drive_revisions"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_revisions"(uuid) to authenticated, service_role;

-- Makes an earlier revision the content again, recorded as a new revision.
create or replace function "better_supabase"."drive_restore_revision"(node uuid, version uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_content jsonb;
  v_file "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_restore_revision.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  select r."content" into v_content from "better_supabase"."versions" r
  where r."id" = drive_restore_revision.version
    and r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text;
  if v_content is null or v_content ->> 'attachmentId' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'revision not found' using errcode = 'P0002', hint = 'DRIVE_REVISION_NOT_FOUND';
  end if;
  select * into v_file from "better_supabase"."attachments" f where f."id" = (v_content ->> 'attachmentId')::uuid;
  if not found then
    raise exception 'the revision''s file was pruned' using errcode = 'P0002', hint = 'DRIVE_REVISION_NOT_FOUND';
  end if;
  update "better_supabase"."drive_nodes" x set "attachment_id" = v_file."id", "preview_pages" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
    v_content, v_file."bucket" || '/' || v_file."object_path", null, 'restore', false, auth.uid());
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_restore_revision"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."drive_restore_revision"(uuid, uuid) to authenticated, service_role;

-- Moves a node and everything under it to the bin in one trash batch.
create or replace function "better_supabase"."drive_trash"(node uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_batch uuid := gen_random_uuid();
  v_count integer := 0;
  v_child record;
  v_id uuid;
  v_locked "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_trash.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item to the bin' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  select * into v_locked from "better_supabase"."drive_nodes" lk
  where lk."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s)
    and (lk."locked_until" > now() and lk."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
  limit 1;
  if found then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_locked."locked_by", 'lockedUntil', v_locked."locked_until")::text;
  end if;
  for v_child in
    select s.node_id, s.depth from "better_supabase"."drive_subtree"(v_node."id") s
    join "better_supabase"."drive_nodes" x on x."id" = s.node_id
    where x."deleted_at" is null
    order by s.depth
  loop
    v_count := v_count + "better_supabase"."trash_cascade"(v_node."tenant_id", 'drive_node', v_child.node_id::text, v_batch, v_child.depth, auth.uid());
  end loop;
  select i."id" into v_id from "better_supabase"."trash_items" i
  where i."subject_type" = 'drive_node' and i."subject_id" = v_node."id"::text;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$$;
revoke execute on function "better_supabase"."drive_trash"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_trash"(uuid) to authenticated, service_role;

-- Restores a bin entry. A name taken in the meantime follows conflict; a
-- parent still in the bin has to be restored first.
create or replace function "better_supabase"."drive_restore"(item uuid, conflict text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_root "better_supabase"."trash_items"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_name text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r.* into v_root from "better_supabase"."trash_items" i
  join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
  where i."id" = drive_restore.item and r."subject_type" = 'drive_node';
  if not found then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_root."subject_id"::uuid;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to restore this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if v_node."parent_id" is not null and exists (
    select 1 from "better_supabase"."drive_nodes" p where p."id" = v_node."parent_id" and p."deleted_at" is not null
  ) then
    raise exception 'restore the folder this item was in first' using errcode = '22023', hint = 'DRIVE_PARENT_TRASHED';
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", null, v_node."parent_id", v_node."name", v_node."id", "better_supabase"."drive_conflict"(drive_restore.conflict));
  if v_name <> v_node."name" then
    update "better_supabase"."drive_nodes" x set "name" = v_name where x."id" = v_node."id";
  end if;
  v_count := "better_supabase"."trash_restore_batch"(v_root."batch_id");
  delete from "better_supabase"."trash_items" where "batch_id" = v_root."batch_id";
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  return jsonb_build_object('id', v_root."id", 'batchId', v_root."batch_id", 'count', v_count, 'node', "better_supabase"."drive_node_json"(v_node));
end;
$$;
revoke execute on function "better_supabase"."drive_restore"(uuid, text) from public, anon;
grant execute on function "better_supabase"."drive_restore"(uuid, text) to authenticated, service_role;

-- The bin: entries the caller may restore, newest first.
create or replace function "better_supabase"."drive_bin"(tenant uuid, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_bin.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', b.item_id, 'batchId', b.batch_id, 'count', b.n, 'trashedBy', b.trashed_by, 'trashedAt', b.trashed_at, 'purgeAfter', b.purge_after, 'node', b.node) order by b.trashed_at desc, b.item_id), '[]'::jsonb)
    from (
      select i."id" as item_id, i."batch_id" as batch_id, i."trashed_by" as trashed_by, i."trashed_at" as trashed_at, i."purge_after" as purge_after,
        (select count(*) from "better_supabase"."trash_items" c where c."batch_id" = i."batch_id")::integer as n,
        "better_supabase"."drive_node_json"(x) as node
      from "better_supabase"."trash_items" i
      join "better_supabase"."drive_nodes" x on x."id"::text = i."subject_id"
      where i."tenant_id" = drive_bin.tenant and i."subject_type" = 'drive_node' and i."depth" = 0
        and (drive_bin.before is null or i."trashed_at" < drive_bin.before)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor'))
      order by i."trashed_at" desc, i."id"
      limit least(greatest(coalesce(drive_bin.page_size, 50), 1), 200)
    ) b
  );
end;
$$;
revoke execute on function "better_supabase"."drive_bin"(uuid, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."drive_bin"(uuid, integer, timestamptz) to authenticated, service_role;

-- Deletes a bin entry for good (the share role, or drive.manage).
create or replace function "better_supabase"."drive_purge"(item uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_root "better_supabase"."trash_items"%rowtype;
begin
  select r.* into v_root from "better_supabase"."trash_items" i
  join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
  where i."id" = drive_purge.item and r."subject_type" = 'drive_node';
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_root."subject_id"::uuid, 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_root."subject_id"::uuid, 'owner')) then
    raise exception 'not allowed to delete this item for good' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  return "better_supabase"."trash_purge_batch"(v_root."batch_id");
end;
$$;
revoke execute on function "better_supabase"."drive_purge"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_purge"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."drive_star"(node uuid, starred boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not "better_supabase"."drive_can"(drive_star.node, 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  insert into "better_supabase"."subject_user_state" ("subject_type", "subject_id", "user_id", "starred_at")
  values ('drive_node', drive_star.node::text, auth.uid(), case when drive_star.starred then now() end)
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "starred_at" = case when drive_star.starred then coalesce("better_supabase"."subject_user_state"."starred_at", now()) end;
  return drive_star.starred;
end;
$$;
revoke execute on function "better_supabase"."drive_star"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."drive_star"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."drive_open"(node uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_open.node and x."deleted_at" is null;
  if not found or auth.uid() is null or not "better_supabase"."drive_can"(v_node."id", 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  insert into "better_supabase"."subject_user_state" ("subject_type", "subject_id", "user_id", "last_opened_at")
  values ('drive_node', v_node."id"::text, auth.uid(), now())
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "last_opened_at" = now();
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_open"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_open"(uuid) to authenticated, service_role;

-- The caller's starred nodes (recent false) or recently opened ones (true).
create or replace function "better_supabase"."drive_marked"(tenant uuid, recent boolean default false, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(t.node order by t.marked_at desc), '[]'::jsonb) from (
    select ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) || jsonb_build_object('starredAt', s."starred_at", 'openedAt', s."last_opened_at") as node,
      case when drive_marked.recent then s."last_opened_at" else s."starred_at" end as marked_at
    from "better_supabase"."subject_user_state" s
    join "better_supabase"."drive_nodes" x on x."id"::text = s."subject_id"
    where s."subject_type" = 'drive_node' and s."user_id" = auth.uid()
      and x."tenant_id" = drive_marked.tenant and x."deleted_at" is null
      and case when drive_marked.recent then s."last_opened_at" else s."starred_at" end is not null
      and "better_supabase"."drive_can"(x."id", 'viewer')
    order by marked_at desc
    limit least(greatest(coalesce(drive_marked.page_size, 50), 1), 200)
  ) t
$$;
revoke execute on function "better_supabase"."drive_marked"(uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."drive_marked"(uuid, boolean, integer) to authenticated, service_role;

-- What a share link on a node opens: the node and, for a folder, its
-- children. node picks an item under the linked folder. For a file, object
-- carries the original for the server to sign a download URL with, unless the
-- link's download_allowed is false or a download block covers the file; previews
-- carries the rendered pages either way. An upload link opens nothing.
create or replace function "better_supabase"."drive_link"(token text, node uuid default null)
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
  v_download boolean;
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select l."id", l."role", l."subject_id", l."expires_at", l."tenant_id"::text, l."download_allowed"
    into v_link_id, v_role, v_root, v_expires, v_tenant, v_download
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(drive_link.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'drive_node'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if v_link_id is null or v_root !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = coalesce(drive_link.node, v_root::uuid)
    and x."tenant_id"::text = v_tenant and x."deleted_at" is null;
  if not found or not (v_root::uuid = any ("better_supabase"."drive_ancestors"(v_node."id"))) then
    raise exception 'this link does not open that item' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if v_role = 'upload' then
    raise exception 'an upload link takes files and opens nothing' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
  end if;
  v_download := coalesce(v_download, true) and not "better_supabase"."drive_download_blocked"(v_node."id");
  return jsonb_build_object(
    'link', jsonb_build_object('id', v_link_id, 'role', v_role, 'nodeId', v_root::uuid, 'expiresAt', v_expires, 'downloadAllowed', v_download),
    'node', "better_supabase"."drive_node_json"(v_node),
    'children', case when v_node."kind" = 'folder' then (
      select coalesce(jsonb_agg("better_supabase"."drive_node_json"(c.r) order by ((c.r)."kind" = 'folder') desc, (c.r)."rank", lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
      from (select y as r from "better_supabase"."drive_nodes" y where y."parent_id" = v_node."id" and y."deleted_at" is null order by (y."kind" = 'folder') desc, y."rank", lower(y."name"), y."id" limit 500) c
    ) end,
    'object', case when v_download then (select jsonb_build_object('bucket', f."bucket", 'path', f."object_path", 'mimeType', f."mime_type", 'status', f."status")
      from "better_supabase"."attachments" f where f."id" = v_node."attachment_id") end,
    'previews', "better_supabase"."drive_preview_json"(v_node)
  );
end;
$$;
revoke all on function "better_supabase"."drive_link"(text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_link"(text, uuid) to anon, authenticated, service_role;

-- Files from people outside the organization: an upload share link on a
-- folder. Needs owner on the folder, as any share link does.
create or replace function "better_supabase"."drive_request_files"(folder uuid, expires_at timestamptz default null, max_uses integer default null, password text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_request_files.folder and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return "better_supabase"."create_share_link"(
    tenant => v_node."tenant_id", subject_type => 'drive_node', subject_id => v_node."id"::text, role => 'upload',
    expires_at => drive_request_files.expires_at, max_uses => drive_request_files.max_uses, password => drive_request_files.password);
end;
$$;
revoke execute on function "better_supabase"."drive_request_files"(uuid, timestamptz, integer, text) from public, anon;
grant execute on function "better_supabase"."drive_request_files"(uuid, timestamptz, integer, text) to authenticated, service_role;

-- One file through an upload link, for the server to upload with the
-- service role and commit: { nodeId, bucket, path, attachment }. The file
-- has no creator and source 'request', and each call counts one use of the
-- link, at most 20 per 1 hour per link unless a drive_link_upload rule says otherwise. A link
-- with a password returns { passwordRequired: true } until the call passes it.
create or replace function "better_supabase"."drive_link_upload"(token text, name text, mime_type text, size bigint, password text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link jsonb := "better_supabase"."resolve_share_link"(drive_link_upload.token, drive_link_upload.password);
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_folder "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
  v_allowed boolean;
  v_retry integer;
begin
  if v_link is null then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if v_link ->> 'id' is null then
    return jsonb_build_object('passwordRequired', true);
  end if;
  if v_link ->> 'subjectType' is distinct from 'drive_node' or v_link ->> 'subjectId' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if v_link ->> 'role' is distinct from 'upload' then
    raise exception 'only an upload link takes files' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
  end if;
  select * into v_folder from "better_supabase"."drive_nodes" x where x."id" = (v_link ->> 'subjectId')::uuid
    and x."tenant_id"::text = v_link ->> 'organizationId' and x."deleted_at" is null;
  if not found or v_folder."kind" <> 'folder' then
    raise exception 'this link does not open that item' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if (coalesce(v_folder."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  select h.allowed, h.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit('drive_link_upload', v_link ->> 'id',
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'drive_link_upload') then null else 20 end,
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'drive_link_upload') then null else '1 hour'::interval end) h;
  if not v_allowed then
    raise exception 'too many uploads through this link' using errcode = 'BS429', hint = 'DRIVE_LINK_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  v_node := "better_supabase"."drive_insert_node"(v_folder."tenant_id", null, v_folder."id", 'file', "better_supabase"."drive_clean_name"(drive_link_upload.name), 'rename', null, 'request');
  v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_link_upload.mime_type, drive_link_upload.size, 'drive_node', v_node."id"::text);
  return jsonb_build_object('nodeId', v_node."id", 'bucket', v_attachment ->> 'bucket', 'path', v_attachment ->> 'object_path', 'attachment', v_attachment);
end;
$$;
revoke all on function "better_supabase"."drive_link_upload"(text, text, text, bigint, text) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_link_upload"(text, text, text, bigint, text) to anon, authenticated, service_role;

-- Puts a tenant tag on a node as a label, or takes it off (applied false),
-- for an editor of the node; tags' own permission and kind checks apply.
create or replace function "better_supabase"."drive_label"(node uuid, tag uuid, applied boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_label.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to label this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if coalesce(drive_label.applied, true) then
    perform "better_supabase"."tag"(v_node."tenant_id", 'drive_node', v_node."id"::text, drive_label.tag);
  else
    perform "better_supabase"."untag"(v_node."tenant_id", 'drive_node', v_node."id"::text, drive_label.tag);
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_label"(uuid, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."drive_label"(uuid, uuid, boolean) to authenticated, service_role;

-- The nodes in a tenant that carry a label and the caller can read.
create or replace function "better_supabase"."drive_labeled"(tenant uuid, tag uuid, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(t.node order by t.ord), '[]'::jsonb) from (
    select ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as node, row_number() over (order by (x."kind" = 'folder') desc, x."rank", lower(x."name"), x."id") as ord
    from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_labeled.tenant and x."deleted_at" is null
      and exists (select 1 from "better_supabase"."taggings" lg where lg."subject_type" = 'drive_node' and lg."subject_id" = x."id"::text and lg."tag_id" = drive_labeled.tag)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
    order by (x."kind" = 'folder') desc, x."rank", lower(x."name"), x."id"
    limit least(greatest(coalesce(drive_labeled.page_size, 50), 1), 200)
  ) t
$$;
revoke execute on function "better_supabase"."drive_labeled"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."drive_labeled"(uuid, uuid, integer) to authenticated, service_role;

-- Asks for approval of one stored version of a file: attachment, or the
-- current one. The request follows those bytes, so a later upload doesn't
-- inherit it and restoring the version brings it back.
create or replace function "better_supabase"."drive_request_approval"(node uuid, attachment uuid default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_revision integer;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_request_approval.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to ask for approval of this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be approved' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_request_approval.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  return "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'approve',
    drive_request_approval.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"))
    || jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'current', v_file."id" = v_node."attachment_id");
end;
$$;
revoke execute on function "better_supabase"."drive_request_approval"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."drive_request_approval"(uuid, uuid, text) to authenticated, service_role;

-- A file's approval requests, newest first, each with the version it is for
-- and whether that version is the current one. Approvals' read rules apply.
create or replace function "better_supabase"."drive_approvals"(node uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_approvals.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(r.value || jsonb_build_object(
      'attachmentId', r.value -> 'payload' ->> 'attachmentId',
      'revision', (r.value -> 'payload' ->> 'revision')::integer,
      'current', r.value -> 'payload' ->> 'attachmentId' = v_node."attachment_id"::text
    ) order by r.ordinality), '[]'::jsonb)
    from jsonb_array_elements("better_supabase"."list_approvals"(v_node."tenant_id", null, false, 'drive_node', v_node."id"::text, 200, null)) with ordinality r
    where r.value ->> 'action' = 'approve'
  );
end;
$$;
revoke execute on function "better_supabase"."drive_approvals"(uuid) from public, anon;
grant execute on function "better_supabase"."drive_approvals"(uuid) to authenticated, service_role;

-- blocks.drive-files.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."drive_create_file"(tenant uuid, parent uuid, name text, mime_type text, size bigint, conflict text default null, fields jsonb default null, drive uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_create_file"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."drive_create_file"(uuid, uuid, text, text, bigint, text, jsonb, uuid) from public, anon;
grant execute on function "api"."drive_create_file"(uuid, uuid, text, text, bigint, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."drive_upload_revision"(node uuid, mime_type text, size bigint)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_upload_revision"($1, $2, $3) $$;
revoke execute on function "api"."drive_upload_revision"(uuid, text, bigint) from public, anon;
grant execute on function "api"."drive_upload_revision"(uuid, text, bigint) to authenticated, service_role;

create or replace function "api"."drive_commit"(node uuid, attachment uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_commit"($1, $2) $$;
revoke execute on function "api"."drive_commit"(uuid, uuid) from public, anon;
grant execute on function "api"."drive_commit"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."drive_object_allowed"(bucket text, path text, action text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_object_allowed"($1, $2, $3) $$;
revoke execute on function "api"."drive_object_allowed"(text, text, text) from public, anon;
grant execute on function "api"."drive_object_allowed"(text, text, text) to authenticated, service_role;

create or replace function "api"."drive_attachment_allowed"(subject_type text, subject_id text, write boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_attachment_allowed"($1, $2, $3) $$;
revoke execute on function "api"."drive_attachment_allowed"(text, text, boolean) from public, anon;
grant execute on function "api"."drive_attachment_allowed"(text, text, boolean) to authenticated, service_role;

create or replace function "api"."drive_prune"(max_objects integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_prune"($1) $$;
revoke execute on function "api"."drive_prune"(integer) from public, anon, authenticated;
grant execute on function "api"."drive_prune"(integer) to service_role;

create or replace function "api"."drive_previews"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_previews"($1) $$;
revoke execute on function "api"."drive_previews"(uuid) from public, anon;
grant execute on function "api"."drive_previews"(uuid) to authenticated, service_role;

create or replace function "api"."drive_set_previews"(node uuid, attachment uuid, pages integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_set_previews"($1, $2, $3) $$;
revoke execute on function "api"."drive_set_previews"(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function "api"."drive_set_previews"(uuid, uuid, integer) to service_role;

create or replace function "api"."drive_revisions"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_revisions"($1) $$;
revoke execute on function "api"."drive_revisions"(uuid) from public, anon;
grant execute on function "api"."drive_revisions"(uuid) to authenticated, service_role;

create or replace function "api"."drive_restore_revision"(node uuid, version uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_restore_revision"($1, $2) $$;
revoke execute on function "api"."drive_restore_revision"(uuid, uuid) from public, anon;
grant execute on function "api"."drive_restore_revision"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."drive_trash"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_trash"($1) $$;
revoke execute on function "api"."drive_trash"(uuid) from public, anon;
grant execute on function "api"."drive_trash"(uuid) to authenticated, service_role;

create or replace function "api"."drive_restore"(item uuid, conflict text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_restore"($1, $2) $$;
revoke execute on function "api"."drive_restore"(uuid, text) from public, anon;
grant execute on function "api"."drive_restore"(uuid, text) to authenticated, service_role;

create or replace function "api"."drive_bin"(tenant uuid, page_size integer default 50, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_bin"($1, $2, $3) $$;
revoke execute on function "api"."drive_bin"(uuid, integer, timestamptz) from public, anon;
grant execute on function "api"."drive_bin"(uuid, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."drive_purge"(item uuid)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_purge"($1) $$;
revoke execute on function "api"."drive_purge"(uuid) from public, anon;
grant execute on function "api"."drive_purge"(uuid) to authenticated, service_role;

create or replace function "api"."drive_star"(node uuid, starred boolean default true)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_star"($1, $2) $$;
revoke execute on function "api"."drive_star"(uuid, boolean) from public, anon;
grant execute on function "api"."drive_star"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."drive_open"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_open"($1) $$;
revoke execute on function "api"."drive_open"(uuid) from public, anon;
grant execute on function "api"."drive_open"(uuid) to authenticated, service_role;

create or replace function "api"."drive_marked"(tenant uuid, recent boolean default false, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_marked"($1, $2, $3) $$;
revoke execute on function "api"."drive_marked"(uuid, boolean, integer) from public, anon;
grant execute on function "api"."drive_marked"(uuid, boolean, integer) to authenticated, service_role;

create or replace function "api"."drive_link"(token text, node uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_link"($1, $2) $$;
revoke execute on function "api"."drive_link"(text, uuid) from public;
grant execute on function "api"."drive_link"(text, uuid) to anon, authenticated, service_role;

create or replace function "api"."drive_request_files"(folder uuid, expires_at timestamptz default null, max_uses integer default null, password text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_request_files"($1, $2, $3, $4) $$;
revoke execute on function "api"."drive_request_files"(uuid, timestamptz, integer, text) from public, anon;
grant execute on function "api"."drive_request_files"(uuid, timestamptz, integer, text) to authenticated, service_role;

create or replace function "api"."drive_link_upload"(token text, name text, mime_type text, size bigint, password text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_link_upload"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."drive_link_upload"(text, text, text, bigint, text) from public;
grant execute on function "api"."drive_link_upload"(text, text, text, bigint, text) to anon, authenticated, service_role;

create or replace function "api"."drive_label"(node uuid, tag uuid, applied boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_label"($1, $2, $3) $$;
revoke execute on function "api"."drive_label"(uuid, uuid, boolean) from public, anon;
grant execute on function "api"."drive_label"(uuid, uuid, boolean) to authenticated, service_role;

create or replace function "api"."drive_labeled"(tenant uuid, tag uuid, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_labeled"($1, $2, $3) $$;
revoke execute on function "api"."drive_labeled"(uuid, uuid, integer) from public, anon;
grant execute on function "api"."drive_labeled"(uuid, uuid, integer) to authenticated, service_role;

create or replace function "api"."drive_request_approval"(node uuid, attachment uuid default null, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_request_approval"($1, $2, $3) $$;
revoke execute on function "api"."drive_request_approval"(uuid, uuid, text) from public, anon;
grant execute on function "api"."drive_request_approval"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."drive_approvals"(node uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_approvals"($1) $$;
revoke execute on function "api"."drive_approvals"(uuid) from public, anon;
grant execute on function "api"."drive_approvals"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
