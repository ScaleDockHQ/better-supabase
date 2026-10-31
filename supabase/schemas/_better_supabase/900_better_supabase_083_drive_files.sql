-- better-supabase module: drive-files
-- @bsb-block drive-files@2 managed
-- @bsb-hash sha256:109f7fc5597d0bdf6a1df3b4c32eb0bf8c085f33fa77d8217b802148c382132b
-- The part of the drive module that needs attachments, versions, trash and share-links: file uploads and revisions with an optional usage quota, extracted text, storage policies, the bin, starred and recent items, folder share links and the purge event. Installed with drive.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
alter table "better_supabase"."drive_nodes" drop constraint if exists bsb_drive_nodes_effective_version;
alter table "better_supabase"."drive_nodes" add constraint bsb_drive_nodes_effective_version foreign key ("effective_version_id") references "better_supabase"."versions" ("id") on delete set null;

-- Whether the caller reaches attachment, stored bytes of node: always for a
-- file outside document control and for the write role; otherwise only the
-- effective version's.
create or replace function "better_supabase"."drive_document_readable"(node uuid, attachment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select x."document_status" is null or "better_supabase"."drive_can"(x."id", 'editor')
      or coalesce(drive_document_readable.attachment = (select (r."content" ->> 'attachmentId')::uuid from "better_supabase"."versions" r where r."id" = x."effective_version_id"), false)
    from "better_supabase"."drive_nodes" x where x."id" = drive_document_readable.node
  ), true)
$$;
revoke execute on function "better_supabase"."drive_document_readable"(uuid, uuid) from public, anon, authenticated;

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
      order by lr."created_at" desc, lr."id" limit 1), 'document', case when ($1)."document_status" is null then null else jsonb_build_object('number', ($1)."document_number", 'type', ($1)."document_type", 'status', ($1)."document_status", 'ownerId', ($1)."document_owner_id", 'effectiveVersionId', ($1)."effective_version_id", 'effectiveVersion', (select r."number" from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveAttachmentId', (select (r."content" ->> 'attachmentId')::uuid from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveFrom', ($1)."effective_from", 'reviewIntervalMonths', ($1)."review_interval_months", 'nextReviewOn', ($1)."next_review_on", 'reviewDue', coalesce(($1)."document_status" = 'effective' and ($1)."next_review_on" <= current_date, false), 'effectiveOnly', not "better_supabase"."drive_can"(($1)."id", 'editor')) end)
$$;
revoke execute on function "better_supabase"."drive_node_json"("better_supabase"."drive_nodes") from public, anon, authenticated;

-- Before a node is deleted for good, its stored objects go into
-- drive_node.purged for the app to remove through Storage; after, its
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
  perform "better_supabase".emit_event('drive_node.purged', jsonb_build_object('organizationId', old."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects), 'drive-nodes/' || old."id"::text, (old."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.purged',
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
      and "better_supabase"."drive_can"(split_part(drive_object_allowed.path, '/', 3)::uuid, 'viewer') and "better_supabase"."drive_document_readable"(split_part(drive_object_allowed.path, '/', 3)::uuid, (select pn."attachment_id" from "better_supabase"."drive_nodes" pn where pn."id"::text = split_part(drive_object_allowed.path, '/', 3)))
  else coalesce((
    select case
      when f."subject_type" is distinct from 'drive_node' then true
      when f."subject_id" !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
      when drive_object_allowed.action = 'select' then "better_supabase"."drive_can_download"(f."subject_id"::uuid) and "better_supabase"."drive_document_readable"(f."subject_id"::uuid, f."id")
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

-- The current content of a file for a text extractor: its node, the stored
-- object and the attachment's scan status, found by node or by the attachment
-- that is a file's content. Null for a folder, a file without content, a node
-- in the bin or an attachment of another record.
create or replace function "better_supabase"."drive_text_source"(node uuid default null, attachment uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('nodeId', s."id", 'organizationId', s."tenant_id", 'name', s."name",
    'attachmentId', f."id", 'bucket', f."bucket", 'path', f."object_path", 'mimeType', f."mime_type",
    'size', f."size", 'status', f."status")
  from "better_supabase"."drive_nodes" s
  join "better_supabase"."attachments" f on f."id" = s."attachment_id"
  where s."id" = coalesce(drive_text_source.node, (select x."id" from "better_supabase"."drive_nodes" x where x."attachment_id" = drive_text_source.attachment limit 1))
    and (drive_text_source.attachment is null or s."attachment_id" = drive_text_source.attachment)
    and s."kind" = 'file' and s."deleted_at" is null
    and f."uploaded_at" is not null
$$;
revoke execute on function "better_supabase"."drive_text_source"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_text_source"(uuid, uuid) to service_role;

-- Stores the text extracted from attachment, the file's content, cut to
-- 1048576 bytes. Null content forgets the file's text. Returns false when
-- attachment is no longer the file's content, so a slow extraction of an
-- older revision never replaces a newer one.
create or replace function "better_supabase"."drive_set_text"(node uuid, attachment uuid, content text, extractor text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_content text := drive_set_text.content;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role stores extracted text' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" s where s."id" = drive_set_text.node for update;
  if not found or v_node."attachment_id" is distinct from drive_set_text.attachment then
    return false;
  end if;
  if v_content is null or btrim(v_content) = '' then
    delete from "better_supabase"."drive_node_texts" t where t."node_id" = v_node."id";
    return true;
  end if;
  if octet_length(v_content) > 1048576 then
    v_content := left(v_content, 1048576);
    while octet_length(v_content) > 1048576 loop
      v_content := left(v_content, length(v_content) - greatest(1, (octet_length(v_content) - 1048576) / 4));
    end loop;
  end if;
  insert into "better_supabase"."drive_node_texts" as t ("node_id", "tenant_id", "attachment_id", "content", "extractor", "extracted_at")
  values (v_node."id", v_node."tenant_id", drive_set_text.attachment, v_content, drive_set_text.extractor, now())
  on conflict ("node_id") do update
    set "tenant_id" = excluded."tenant_id", "attachment_id" = excluded."attachment_id", "content" = excluded."content", "extractor" = excluded."extractor", "extracted_at" = excluded."extracted_at";
  return true;
end;
$$;
revoke execute on function "better_supabase"."drive_set_text"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_set_text"(uuid, uuid, text, text) to service_role;

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
  if "better_supabase"."drive_sharing"(v_node."tenant_id") ->> 'links' = 'none' then
    raise exception 'this organization has turned off share links' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  if "better_supabase"."drive_sharing"(v_node."tenant_id") ->> 'links' = 'organization' and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = auth.uid()
  ) then
    raise exception 'sign in as a member of this organization to open this link' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
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
  if "better_supabase"."drive_sharing"(v_folder."tenant_id") ->> 'links' = 'none' then
    raise exception 'this organization has turned off share links' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  if "better_supabase"."drive_sharing"(v_folder."tenant_id") ->> 'links' = 'organization' and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_folder."tenant_id" and mu."user_id" = auth.uid()
  ) then
    raise exception 'sign in as a member of this organization to open this link' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
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

-- Puts a file under document control, or changes its type, owner or review
-- interval: a new document gets the next number and starts as a draft.
create or replace function "better_supabase"."drive_document_save"(node uuid, document_type text, owner_id uuid default null, review_interval_months integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
  v_entity text;
  v_format text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    case drive_document_save.document_type
      when 'sop' then
        v_entity := 'drive_document_sop';
        v_format := 'SOP-{n:4}';
      else
        v_entity := 'drive_document';
        v_format := 'DOC-{n:5}';
    end case;
    if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_node."tenant_id", v_entity, v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", v_entity, now());
    v_number := better_supabase.format_assigned_number(v_format, v_seq, now());
  end if;
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive_node.document_saved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.document_saved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_document_save"(uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."drive_document_save"(uuid, text, uuid, integer) to authenticated, service_role;

-- Sends a draft or an effective document's attachment (the current one by
-- default) for release through an approval request with action release. A
-- draft moves to in_review; an effective document stays effective, so its
-- readers keep the released version until the new one is approved.
create or replace function "better_supabase"."drive_document_submit"(node uuid, attachment uuid default null, reason text default null)
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
  v_request jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_submit.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to submit this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."document_status" is null then
    raise exception 'save the file as a controlled document first' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if not (v_node."document_status" = 'draft' or (v_node."document_status" in ('in_review', 'effective') and not exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."subject_type" = 'drive_node' and q."subject_id" = v_node."id"::text
      and q."action" = 'release' and q."status" = 'pending'
  ))) then
    raise exception 'only a draft, or an effective document without a pending release, can be submitted' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_document_submit.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  if v_node."document_status" = 'draft' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'in_review', drive_document_submit.reason);
  end if;
  v_request := "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'release',
    drive_document_submit.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"));
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.submitted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id'), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.submitted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document submitted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id')
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_document_submit"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."drive_document_submit"(uuid, uuid, text) to authenticated, service_role;

-- Makes attachment the document's effective version: its version is frozen
-- and labelled effective, the previous one is labelled superseded, and the
-- next review falls review_interval_months later (options.control.reviewMonths
-- by default). The service role calls it, and so does an approved release
-- request through drive_document_decided.
create or replace function "better_supabase"."drive_document_release"(node uuid, attachment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_version uuid;
  v_inserted jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."id"::text = nullif(current_setting('better_supabase.approval', true), '')
      and q."status" = 'approved' and q."action" = 'release'
      and q."subject_type" = 'drive_node' and q."subject_id" = drive_document_release.node::text
  )) then
    raise exception 'only an approved release request releases a document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_release.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    raise exception 'only a document in review or an effective one can be released' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = drive_document_release.attachment
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."id" into v_version from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" desc limit 1;
  if v_version is null then
    v_inserted := "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", 'effective', 'manual', true, auth.uid());
    v_version := (v_inserted ->> 'id')::uuid;
  else
    update "better_supabase"."versions" r set "label" = 'effective', "frozen" = true where r."id" = v_version;
  end if;
  update "better_supabase"."versions" r set "label" = 'superseded'
  where r."id" = v_node."effective_version_id" and r."id" <> v_version;
  update "better_supabase"."drive_nodes" x set "effective_version_id" = v_version, "effective_from" = now(),
    "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
  where x."id" = v_node."id";
  if v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'effective', 'released');
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_document_release"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_document_release"(uuid, uuid) to service_role;

-- Runs when approvals decides a release request: an approval releases the
-- attachment it names, a rejection sends a document in review back to draft
-- and leaves an effective one as it is. Other actions on the file pass.
create or replace function "better_supabase"."drive_document_decided"(request uuid, approved boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" q where q."id" = drive_document_decided.request;
  if not found or v_req."action" <> 'release' or v_req."subject_type" <> 'drive_node' then
    return;
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id"::text = v_req."subject_id" for update;
  if not found or v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    return;
  end if;
  if drive_document_decided.approved then
    perform set_config('better_supabase.approval', v_req."id"::text, true);
    perform "better_supabase"."drive_document_release"(v_node."id", coalesce((v_req."payload" ->> 'attachmentId')::uuid, v_node."attachment_id"));
    perform set_config('better_supabase.approval', '', true);
  elsif v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', 'rejected');
  end if;
end;
$$;
revoke execute on function "better_supabase"."drive_document_decided"(uuid, boolean) from public, anon, authenticated;

-- Withdraws an effective document: it stays readable as obsolete and can't
-- be submitted again. Needs options.control.releaseRole on the file.
create or replace function "better_supabase"."drive_document_obsolete"(node uuid, reason text)
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
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_obsolete.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be obsoleted' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to withdraw this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document can be made obsolete' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'obsolete', drive_document_obsolete.reason);
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.obsoleted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.obsoleted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document made obsolete',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_document_obsolete"(uuid, text) from public, anon;
grant execute on function "better_supabase"."drive_document_obsolete"(uuid, text) to authenticated, service_role;

-- Records a periodic review of an effective document by its owner or a
-- writer. unchanged moves the next review on by the interval; revise leaves
-- the document effective until a new version is submitted and released.
create or replace function "better_supabase"."drive_document_review"(node uuid, outcome text, note text default null)
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
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_review.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be reviewed' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_node."document_owner_id" = auth.uid() or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to review this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_document_review.outcome is null or drive_document_review.outcome not in ('unchanged', 'revise') then
    raise exception 'outcome must be unchanged or revise' using errcode = '22023', hint = 'DRIVE_DOCUMENT_REVIEW_INVALID';
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document is reviewed' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_review.outcome = 'unchanged' then
    update "better_supabase"."drive_nodes" x set "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  perform "better_supabase".emit_event('drive_node.reviewed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.reviewed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document reviewed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$$;
revoke execute on function "better_supabase"."drive_document_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."drive_document_review"(uuid, text, text) to authenticated, service_role;

-- The document register of an organization: its controlled files the caller
-- reads, by number. filters takes type, status, ownerId, reviewDue (true for
-- effective documents whose review date has come) and search (number or name).
create or replace function "better_supabase"."drive_documents"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if jsonb_typeof(coalesce(drive_documents.filters, '{}'::jsonb)) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) order by x."document_number")
    from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_documents.tenant and x."document_status" is not null and x."deleted_at" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
      and (drive_documents.filters ->> 'type' is null or x."document_type" = drive_documents.filters ->> 'type')
      and (drive_documents.filters ->> 'status' is null or x."document_status" = drive_documents.filters ->> 'status')
      and (drive_documents.filters ->> 'ownerId' is null or x."document_owner_id"::text = drive_documents.filters ->> 'ownerId')
      and (coalesce((drive_documents.filters ->> 'reviewDue')::boolean, false) = false
        or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
      and (coalesce(drive_documents.filters ->> 'search', '') = ''
        or x."document_number" ilike '%' || (drive_documents.filters ->> 'search') || '%'
        or x."name" ilike '%' || (drive_documents.filters ->> 'search') || '%')
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."drive_documents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."drive_documents"(uuid, jsonb) to authenticated, service_role;

-- Reports each effective document whose review date has come once per date:
-- a drive_node.review_requested event and, with notifications, a notification
-- to its owner. Run it daily from a job.
create or replace function "better_supabase"."notify_due_drive_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  for v_node in
    select * from "better_supabase"."drive_nodes" x
    where x."document_status" = 'effective' and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on" and x."deleted_at" is null
    for update skip locked
  loop
    perform "better_supabase".emit_event('drive_node.review_requested', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'ownerId', v_node."document_owner_id", 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
    if v_node."document_owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'drive.document_review_due',
        'tenant', v_node."tenant_id",
        'actor', null,
        'subject_type', 'drive_node',
        'subject_id', v_node."id"::text,
        'summary', v_node."document_number" || ' ' || v_node."name",
        'recipients', to_jsonb(array[v_node."document_owner_id"]),
        'key', 'drive.document_review_due:' || v_node."id"::text || ':' || v_node."next_review_on"::text,
        'data', jsonb_build_object('nodeId', v_node."id", 'documentNumber', v_node."document_number", 'nextReviewOn', v_node."next_review_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."drive_nodes" x set "review_notified_for" = v_node."next_review_on" where x."id" = v_node."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_drive_reviews"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_drive_reviews"() to service_role;

-- The retention policy kind of a label: drive_label_ and the name in lower
-- case, every run of other characters as one underscore.
create or replace function "better_supabase"."drive_retention_kind"(label text)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'drive_label_' || left(coalesce(nullif(btrim(regexp_replace(lower(drive_retention_kind.label), '[^a-z0-9]+', '_', 'g'), '_'), ''), 'label'), 50)
$$;
revoke execute on function "better_supabase"."drive_retention_kind"(text) from public, anon;
grant execute on function "better_supabase"."drive_retention_kind"(text) to authenticated, service_role;

-- Moves the nodes whose label policy has run out into the bin, oldest first.
-- A node under a hold or a check-out is skipped. Returns how many it binned.
create or replace function "better_supabase"."drive_retention_sweep"(tenant uuid default null, batch_size integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node uuid;
  v_binned integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'not allowed to sweep retention' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  for v_node in
    select x."id" from "better_supabase"."drive_nodes" x
    where (drive_retention_sweep.tenant is null or x."tenant_id" = drive_retention_sweep.tenant) and x."deleted_at" is null
      and exists (
        select 1 from "better_supabase"."taggings" lg
        join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
        where lg."subject_type" = 'drive_node' and lg."subject_id" = x."id"::text
          and "better_supabase"."retention_for"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text) is not null
          and coalesce(x."updated_at", x."created_at") < now() - "better_supabase"."retention_for"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
          and not "better_supabase"."is_held"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
      )
      and not "better_supabase"."drive_node_held"(x."id")
    order by coalesce(x."updated_at", x."created_at"), x."id"
    limit least(greatest(coalesce(drive_retention_sweep.batch_size, 100), 1), 1000)
  loop
    begin
      perform "better_supabase"."drive_trash"(v_node);
      v_binned := v_binned + 1;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v_binned;
end;
$$;
revoke execute on function "better_supabase"."drive_retention_sweep"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."drive_retention_sweep"(uuid, integer) to service_role;

-- Moving a node into the bin or back changes it for the feed and for retention.
create or replace function "better_supabase"."drive_node_bin_touch"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new."deleted_at" is distinct from old."deleted_at" then
    new."updated_at" := now();
  end if;
  return new;
end;
$$;
drop trigger if exists "bsb_drive_node_bin_touch" on "better_supabase"."drive_nodes";
create trigger "bsb_drive_node_bin_touch"
  before update of "deleted_at" on "better_supabase"."drive_nodes"
  for each row execute function "better_supabase"."drive_node_bin_touch"();

-- The nodes that changed after a cursor, oldest first, that the caller can
-- read. Changes from the last five seconds wait, so a transaction that
-- commits late isn't skipped.
create or replace function "better_supabase"."drive_changes"(tenant uuid, after text default null, page_size integer default 200, drive uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(drive_changes.page_size, 200), 1), 500);
  v_row "better_supabase"."drive_nodes"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_more boolean := false;
  v_cursor text := drive_changes.after;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_changes.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_changes.after is not null then
    begin
      v_at := split_part(drive_changes.after, '|', 1)::timestamptz;
      v_id := split_part(drive_changes.after, '|', 2)::uuid;
    exception when others then
      raise exception 'the changes cursor is not valid' using errcode = '22023', hint = 'DRIVE_CURSOR_INVALID';
    end;
  end if;
  for v_row in
    select * from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_changes.tenant
      and (v_at is null or (x."updated_at", x."id") > (v_at, v_id))
      and x."updated_at" <= now() - interval '5 seconds'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
    order by x."updated_at", x."id"
    limit v_size + 1
  loop
    v_count := v_count + 1;
    if v_count > v_size then
      v_more := true;
      exit;
    end if;
    v_items := v_items || jsonb_build_array(case when v_row."deleted_at" is not null
        then jsonb_build_object('removed', true, 'id', v_row."id")
        else jsonb_build_object('removed', false, 'node', ("better_supabase"."drive_node_json"(v_row) || jsonb_build_object('role', "better_supabase"."drive_role"((v_row)."id"), 'readOnly', (coalesce((v_row)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_row)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_row)."id")))) end);
    v_cursor := to_char(v_row."updated_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || v_row."id"::text;
  end loop;
  return jsonb_build_object('changes', v_items, 'cursor', v_cursor, 'more', v_more);
end;
$$;
revoke execute on function "better_supabase"."drive_changes"(uuid, text, integer, uuid) from public, anon;
grant execute on function "better_supabase"."drive_changes"(uuid, text, integer, uuid) to authenticated, service_role;

create or replace function "better_supabase"."drive_guest_sharing"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."subject_type" = 'drive_node'
    and ("better_supabase"."drive_sharing"(new."tenant_id") ->> 'guests')::boolean is false then
    raise exception 'this organization has turned off sharing drive items with guests' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."drive_guest_sharing"() from public, anon, authenticated;
drop trigger if exists "bsb_drive_guest_sharing" on "better_supabase"."guest_grants";
create trigger "bsb_drive_guest_sharing"
  before insert or update of "subject_type", "subject_id" on "better_supabase"."guest_grants"
  for each row execute function "better_supabase"."drive_guest_sharing"();

-- blocks.drive-files.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

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

create or replace function "api"."drive_text_source"(node uuid default null, attachment uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_text_source"($1, $2) $$;
revoke execute on function "api"."drive_text_source"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."drive_text_source"(uuid, uuid) to service_role;

create or replace function "api"."drive_set_text"(node uuid, attachment uuid, content text, extractor text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_set_text"($1, $2, $3, $4) $$;
revoke execute on function "api"."drive_set_text"(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."drive_set_text"(uuid, uuid, text, text) to service_role;

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

create or replace function "api"."drive_document_save"(node uuid, document_type text, owner_id uuid default null, review_interval_months integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_document_save"($1, $2, $3, $4) $$;
revoke execute on function "api"."drive_document_save"(uuid, text, uuid, integer) from public, anon;
grant execute on function "api"."drive_document_save"(uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."drive_document_submit"(node uuid, attachment uuid default null, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_document_submit"($1, $2, $3) $$;
revoke execute on function "api"."drive_document_submit"(uuid, uuid, text) from public, anon;
grant execute on function "api"."drive_document_submit"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."drive_document_release"(node uuid, attachment uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_document_release"($1, $2) $$;
revoke execute on function "api"."drive_document_release"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."drive_document_release"(uuid, uuid) to service_role;

create or replace function "api"."drive_document_obsolete"(node uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_document_obsolete"($1, $2) $$;
revoke execute on function "api"."drive_document_obsolete"(uuid, text) from public, anon;
grant execute on function "api"."drive_document_obsolete"(uuid, text) to authenticated, service_role;

create or replace function "api"."drive_document_review"(node uuid, outcome text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_document_review"($1, $2, $3) $$;
revoke execute on function "api"."drive_document_review"(uuid, text, text) from public, anon;
grant execute on function "api"."drive_document_review"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."drive_documents"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_documents"($1, $2) $$;
revoke execute on function "api"."drive_documents"(uuid, jsonb) from public, anon;
grant execute on function "api"."drive_documents"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."notify_due_drive_reviews"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_due_drive_reviews"() $$;
revoke execute on function "api"."notify_due_drive_reviews"() from public, anon, authenticated;
grant execute on function "api"."notify_due_drive_reviews"() to service_role;

create or replace function "api"."drive_retention_kind"(label text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_retention_kind"($1) $$;
revoke execute on function "api"."drive_retention_kind"(text) from public, anon;
grant execute on function "api"."drive_retention_kind"(text) to authenticated, service_role;

create or replace function "api"."drive_retention_sweep"(tenant uuid default null, batch_size integer default 100)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_retention_sweep"($1, $2) $$;
revoke execute on function "api"."drive_retention_sweep"(uuid, integer) from public, anon, authenticated;
grant execute on function "api"."drive_retention_sweep"(uuid, integer) to service_role;

create or replace function "api"."drive_changes"(tenant uuid, after text default null, page_size integer default 200, drive uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."drive_changes"($1, $2, $3, $4) $$;
revoke execute on function "api"."drive_changes"(uuid, text, integer, uuid) from public, anon;
grant execute on function "api"."drive_changes"(uuid, text, integer, uuid) to authenticated, service_role;

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
