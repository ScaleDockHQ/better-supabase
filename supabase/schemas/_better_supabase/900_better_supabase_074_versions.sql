-- better-supabase module: versions
-- @bsb-block versions@2 managed
-- @bsb-hash sha256:da81da12ec5f5e322133675e4fa52aeab65335241cae95503224cf877cfe1928
-- Numbered snapshots of a subject's content: manual, debounced auto and frozen snapshots, restore through columns or an apply function, and retention.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "number" integer not null constraint bsb_versions_number_check check ("number" > 0),
  "label" text constraint bsb_versions_label_check check (length("label") >= 1 and length("label") <= 120),
  "content" jsonb,
  "storage_path" text,
  "content_hash" text not null,
  "file_hash" text constraint bsb_versions_file_hash_check check ("file_hash" ~ '^[0-9a-f]{64}$'),
  "hash_version" smallint not null default 1 constraint bsb_versions_hash_version_check check ("hash_version" in (1, 2)),
  "source" text not null default 'manual' constraint bsb_versions_source_check check ("source" in ('manual', 'auto', 'restore')),
  "frozen" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "number"),
  constraint bsb_versions_check check ("content" is not null or "storage_path" is not null)
);
-- A hash_version 1 version hashes its content and storage path; version 2
-- hashes its content and the SHA-256 of the file's bytes (file_hash).

create index "versions_tenant_idx" on "better_supabase"."versions" ("tenant_id");
alter table "better_supabase"."versions" enable row level security;
revoke all on "better_supabase"."versions" from public, anon, authenticated;
grant select on "better_supabase"."versions" to authenticated;
grant all on "better_supabase"."versions" to service_role;
create policy bsb_versions_read on "better_supabase"."versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('versions.read')));
create policy bsb_versions_ai_documents on "better_supabase"."versions" as restrictive
  for select to authenticated
  using ("subject_type" <> 'ai_document');

-- Writes a version, numbered per subject. A version without a label whose
-- content matches the latest is not written again; an auto snapshot within
-- the debounce window of the previous auto snapshot replaces its content.
-- Keeps the newest 50 versions without a label or freeze.

create or replace function "better_supabase"."version_insert"(tenant uuid, subject_type text, subject_id text, content jsonb, storage_path text, label text, source text, frozen boolean, actor uuid, file_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := case when version_insert.file_sha256 is null
    then encode(extensions.digest(coalesce(version_insert.content::text, '') || coalesce(version_insert.storage_path, ''), 'sha256'), 'hex')
    else encode(extensions.digest(coalesce(version_insert.content::text, '') || version_insert.file_sha256, 'sha256'), 'hex') end;
  v_hash_version smallint := case when version_insert.file_sha256 is null then 1 else 2 end;
  v_last_id uuid;
  v_last_number integer;
  v_last_hash text;
  v_last_open boolean;
  v_last_source text;
  v_last_at timestamptz;
  v_id uuid;
  v_number integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('better_supabase.version:' || version_insert.subject_type || ':' || version_insert.subject_id, 0));
  select v."id", v."number", v."content_hash", v."label" is null and not v."frozen", v."source", v."created_at"
    into v_last_id, v_last_number, v_last_hash, v_last_open, v_last_source, v_last_at
    from "better_supabase"."versions" v
    where v."subject_type" = version_insert.subject_type and v."subject_id" = version_insert.subject_id
    order by v."number" desc
    limit 1;
  if v_last_id is not null and version_insert.label is null and not version_insert.frozen and v_last_hash = v_hash then
    return jsonb_build_object('id', v_last_id, 'number', v_last_number, 'contentHash', v_hash, 'unchanged', true);
  end if;
  if version_insert.source = 'auto' and version_insert.label is null and not version_insert.frozen
    and v_last_open and v_last_source = 'auto' and v_last_at > now() - make_interval(secs => 300) then
    update "better_supabase"."versions"
      set "content" = version_insert.content, "storage_path" = version_insert.storage_path, "content_hash" = v_hash, "file_hash" = version_insert.file_sha256, "hash_version" = v_hash_version
      where "id" = v_last_id;
    return jsonb_build_object('id', v_last_id, 'number', v_last_number, 'contentHash', v_hash, 'unchanged', false);
  end if;
  v_number := coalesce(v_last_number, 0) + 1;
  insert into "better_supabase"."versions" ("tenant_id", "subject_type", "subject_id", "number", "label", "content", "storage_path", "content_hash", "file_hash", "hash_version", "source", "frozen", "created_by", "created_at")
  values (version_insert.tenant, version_insert.subject_type, version_insert.subject_id, v_number, version_insert.label, version_insert.content, version_insert.storage_path, v_hash, version_insert.file_sha256, v_hash_version, version_insert.source, version_insert.frozen, version_insert.actor, now())
  returning "id" into v_id;
  delete from "better_supabase"."versions" v
  where v."subject_type" = version_insert.subject_type and v."subject_id" = version_insert.subject_id
    and v."label" is null and not v."frozen"
    and v."id" not in (
      select x."id" from "better_supabase"."versions" x
      where x."subject_type" = version_insert.subject_type and x."subject_id" = version_insert.subject_id
        and x."label" is null and not x."frozen"
      order by x."number" desc
      limit 50
    );
  perform "better_supabase".emit_event('version.created', jsonb_build_object('organizationId', version_insert.tenant, 'subjectType', version_insert.subject_type, 'subjectId', version_insert.subject_id, 'id', v_id, 'number', v_number, 'label', version_insert.label, 'source', version_insert.source), 'versions/' || v_id::text, (version_insert.tenant)::text, null, 'better-supabase/versions');
  return jsonb_build_object('id', v_id, 'number', v_number, 'contentHash', v_hash, 'unchanged', false);
end;
$$;
revoke execute on function "better_supabase"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) to service_role;

-- fields: the extra columns (columns your schema files add) to set
-- on the version written, or on the latest one when the content is unchanged.

create or replace function "better_supabase"."snapshot_version"(tenant uuid, subject_type text, subject_id text, content jsonb default null, label text default null, storage_path text default null, file_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_content jsonb := snapshot_version.content;
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', snapshot_version.tenant, 'versions.create'), false) and case snapshot_version.subject_type
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (snapshot_version.subject_id)::uuid and s."organization_id" = snapshot_version.tenant)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (snapshot_version.subject_id)::uuid and s."organization_id" = snapshot_version.tenant) and coalesce(better_supabase.can('tenant', snapshot_version.tenant, 'customers.read'), false)
    else false
  end and snapshot_version.subject_type <> 'ai_document')) then
    raise exception 'not allowed to snapshot this record' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  if snapshot_version.file_sha256 is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role records a file hash' using errcode = '42501', hint = 'VERSION_HASH_FORBIDDEN';
  end if;
  if v_content is null and snapshot_version.storage_path is null then
    case snapshot_version.subject_type
    when 'project' then
      select jsonb_object_agg(e.key, e.value) into v_content
      from "public"."projects" s, jsonb_each(to_jsonb(s)) e
      where s."id" = (snapshot_version.subject_id)::uuid
        and e.key = any ('{name,budget_minor,currency}'::text[]);
    when 'customer' then
      select jsonb_object_agg(e.key, e.value) into v_content
      from "public"."customers" s, jsonb_each(to_jsonb(s)) e
      where s."id" = (snapshot_version.subject_id)::uuid
        and e.key = any ('{name,kvk}'::text[]);
    else null;
  end case;
    if v_content is null then
      raise exception 'pass content or a storage path, or list the subject''s columns' using errcode = '22023', hint = 'VERSION_CONTENT_REQUIRED';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_version_snapshot"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using snapshot_version.tenant, snapshot_version.subject_type, snapshot_version.subject_id;
    end if;
  end;
  v_result := "better_supabase"."version_insert"(snapshot_version.tenant, snapshot_version.subject_type, snapshot_version.subject_id, v_content, snapshot_version.storage_path, nullif(trim(snapshot_version.label), ''), 'manual', false, auth.uid(), snapshot_version.file_sha256);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_version_snapshot"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using (v_result ->> 'id')::uuid, snapshot_version.subject_type, snapshot_version.subject_id;
    end if;
  end;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."snapshot_version"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "better_supabase"."snapshot_version"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_versions"(tenant uuid, subject_type text, subject_id text, page_size integer default 50, before integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', list_versions.tenant, 'versions.read'), false) and case list_versions.subject_type
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (list_versions.subject_id)::uuid and s."organization_id" = list_versions.tenant)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (list_versions.subject_id)::uuid and s."organization_id" = list_versions.tenant) and coalesce(better_supabase.can('tenant', list_versions.tenant, 'customers.read'), false)
    else false
  end and list_versions.subject_type <> 'ai_document')) then
    raise exception 'not allowed to read these versions' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'number', v."number", 'label', v."label", 'source', v."source", 'frozen', v."frozen", 'contentHash', v."content_hash", 'storagePath', v."storage_path", 'fileSha256', v."file_hash", 'hashVersion', v."hash_version", 'subjectType', v."subject_type", 'subjectId', v."subject_id", 'createdBy', v."created_by", 'createdAt', v."created_at") order by v."number" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."versions" x
    where x."tenant_id" = list_versions.tenant
      and x."subject_type" = list_versions.subject_type
      and x."subject_id" = list_versions.subject_id
      and (list_versions.before is null or x."number" < list_versions.before)
    order by x."number" desc
    limit least(greatest(coalesce(list_versions.page_size, 50), 1), 200)
  ) v;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_versions"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_versions"(uuid, text, text, integer, integer) to authenticated, service_role;

create or replace function "better_supabase"."get_version"(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."versions"%rowtype;
begin
  select * into v_row from "better_supabase"."versions" where "id" = get_version.version_id;
  if not found then
    raise exception 'version not found' using errcode = 'P0002', hint = 'VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'versions.read'), false) and case v_row."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    else false
  end and v_row."subject_type" <> 'ai_document')) then
    raise exception 'not allowed to read these versions' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'number', v_row."number", 'label', v_row."label", 'source', v_row."source", 'frozen', v_row."frozen", 'contentHash', v_row."content_hash", 'storagePath', v_row."storage_path", 'fileSha256', v_row."file_hash", 'hashVersion', v_row."hash_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at") || jsonb_build_object('content', v_row."content");
end;
$$;
revoke execute on function "better_supabase"."get_version"(uuid) from public, anon;
grant execute on function "better_supabase"."get_version"(uuid) to authenticated, service_role;

-- Many versions with their content in one read, in the order requested. The
-- read check runs once per distinct record; a version that is missing or that
-- the caller cannot read is left out instead of failing the batch.
create or replace function "better_supabase"."get_versions"(version_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return (
  with wanted as (
    select x.* from "better_supabase"."versions" x where x."id" = any (get_versions.version_ids)
  ),
  allowed as materialized (
    select q."tenant_id", q."subject_type", q."subject_id"
    from (select distinct w."tenant_id", w."subject_type", w."subject_id" from wanted w) q
    where coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', q."tenant_id", 'versions.read'), false) and case q."subject_type"
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (q."subject_id")::uuid and s."organization_id" = q."tenant_id")
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (q."subject_id")::uuid and s."organization_id" = q."tenant_id") and coalesce(better_supabase.can('tenant', q."tenant_id", 'customers.read'), false)
    else false
  end and q."subject_type" <> 'ai_document')
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'number', v."number", 'label', v."label", 'source', v."source", 'frozen', v."frozen", 'contentHash', v."content_hash", 'storagePath', v."storage_path", 'fileSha256', v."file_hash", 'hashVersion', v."hash_version", 'subjectType', v."subject_type", 'subjectId', v."subject_id", 'createdBy', v."created_by", 'createdAt', v."created_at") || jsonb_build_object('content', v."content") order by array_position(get_versions.version_ids, v."id")), '[]'::jsonb)
  from wanted v
  join allowed a on a."tenant_id" = v."tenant_id" and a."subject_type" = v."subject_type" and a."subject_id" = v."subject_id"
  );
end;
$$;
revoke execute on function "better_supabase"."get_versions"(uuid[]) from public, anon;
grant execute on function "better_supabase"."get_versions"(uuid[]) to authenticated, service_role;

-- A share link pinned to a version (create_share_link's version_id) reads
-- that version with the token alone, for anon. Volatile: resolving the link
-- counts a use.
create or replace function "better_supabase"."get_shared_version"(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_link jsonb;
  v_row "better_supabase"."versions"%rowtype;
begin
  if get_shared_version.token is null or get_shared_version.token !~ '^[0-9a-f]{48}$' then
    return null;
  end if;
  v_link := "better_supabase"."resolve_share_link"(get_shared_version.token);
  if v_link is null or v_link ->> 'versionId' is null then
    return null;
  end if;
  select * into v_row from "better_supabase"."versions"
  where "id" = (v_link ->> 'versionId')::uuid
    and "subject_type" = v_link ->> 'subjectType'
    and "subject_id" = v_link ->> 'subjectId';
  if not found then
    return null;
  end if;
  return (jsonb_build_object('id', v_row."id", 'number', v_row."number", 'label', v_row."label", 'source', v_row."source", 'frozen', v_row."frozen", 'contentHash', v_row."content_hash", 'storagePath', v_row."storage_path", 'fileSha256', v_row."file_hash", 'hashVersion', v_row."hash_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at") - 'createdBy') || jsonb_build_object('content', v_row."content");
end;
$$;
revoke all on function "better_supabase"."get_shared_version"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."get_shared_version"(text) to anon, authenticated, service_role;


-- Writes a version's content back to its subject, through the subject's apply
-- function or its columns, then records the result as a new version. With
-- fields, only those keys come from the version and the rest keep the row's
-- current values, so the subject needs columns to read them from.

create or replace function "better_supabase"."restore_version"(version_id uuid, fields text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_number integer;
  v_content jsonb;
  v_current jsonb;
  v_result jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "subject_type", "subject_id", "number", "content"
    into v_tenant, v_subject_type, v_subject_id, v_number, v_content
    from "better_supabase"."versions" where "id" = restore_version.version_id;
  if v_subject_type is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'versions.restore'), false) and case v_subject_type
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_subject_id)::uuid and s."organization_id" = v_tenant)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    else false
  end and case v_subject_type
    when 'customer' then coalesce(better_supabase.can('tenant', v_tenant, 'customers.write'), false)
    else true
  end and v_subject_type <> 'ai_document')) then
    raise exception 'not allowed to restore this version' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  if v_content is null then
    raise exception 'a version kept in Storage is restored by the app' using errcode = '22023', hint = 'VERSION_RESTORE_UNSUPPORTED';
  end if;
  if restore_version.fields is not null then
    if cardinality(restore_version.fields) = 0 then
      raise exception 'list at least one field to restore, or pass null to restore the whole version' using errcode = '22023', hint = 'VERSION_FIELDS_EMPTY';
    end if;
    if exists (select 1 from unnest(restore_version.fields) f where not (v_content ? f)) then
      raise exception 'a field to restore is not in this version' using errcode = '22023', hint = 'VERSION_FIELD_UNKNOWN';
    end if;
    case v_subject_type
    when 'project' then
      select jsonb_object_agg(e.key, e.value) into v_current
      from "public"."projects" s, jsonb_each(to_jsonb(s)) e
      where s."id" = (v_subject_id)::uuid
        and e.key = any ('{name,budget_minor,currency}'::text[]);
    when 'customer' then
      select jsonb_object_agg(e.key, e.value) into v_current
      from "public"."customers" s, jsonb_each(to_jsonb(s)) e
      where s."id" = (v_subject_id)::uuid
        and e.key = any ('{name,kvk}'::text[]);
    else null;
  end case;
    if v_current is null then
      raise exception 'this subject type has no columns to keep, so it restores whole versions only' using errcode = '22023', hint = 'VERSION_RESTORE_UNSUPPORTED';
    end if;
    v_content := v_current || (
      select jsonb_object_agg(e.key, e.value) from jsonb_each(v_content) e
      where e.key = any (restore_version.fields)
    );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_version_restore"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using restore_version.version_id;
    end if;
  end;
  perform set_config('better_supabase.restoring_version', 'on', true);
  case v_subject_type
    when 'project' then
      update "public"."projects" s set "name" = r."name", "budget_minor" = r."budget_minor", "currency" = r."currency"
      from jsonb_populate_record(null::"public"."projects", v_content) r
      where s."id" = (v_subject_id)::uuid;
    when 'customer' then
      update "public"."customers" s set "name" = r."name", "kvk" = r."kvk"
      from jsonb_populate_record(null::"public"."customers", v_content) r
      where s."id" = (v_subject_id)::uuid;
    else
      raise exception 'this subject type has no columns or apply function to restore into' using errcode = '22023', hint = 'VERSION_RESTORE_UNSUPPORTED';
  end case;
  perform set_config('better_supabase.restoring_version', '', true);
  v_result := "better_supabase"."version_insert"(v_tenant, v_subject_type, v_subject_id, v_content, null, null, 'restore', false, auth.uid());
  perform "better_supabase".emit_event('version.restored', jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', (v_result ->> 'id')::uuid, 'number', (v_result ->> 'number')::integer, 'restoredFrom', v_number, 'fields', to_jsonb(restore_version.fields)), 'versions/' || (v_result ->> 'id'), (v_tenant)::text, null, 'better-supabase/versions');
  perform better_supabase.audit_event(
    event_type => 'version.restored',
    category => 'data',
    target_type => 'version',
    record_id => restore_version.version_id::text,
    summary => 'restored version ' || v_number::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', (v_result ->> 'id')::uuid, 'number', (v_result ->> 'number')::integer, 'restoredFrom', v_number, 'fields', to_jsonb(restore_version.fields))
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_version_restore"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using restore_version.version_id, (v_result ->> 'id')::uuid;
    end if;
  end;
  return v_result || jsonb_build_object('content', v_content, 'restoredFrom', v_number);
end;
$$;
revoke execute on function "better_supabase"."restore_version"(uuid, text[]) from public, anon;
grant execute on function "better_supabase"."restore_version"(uuid, text[]) to authenticated, service_role;

-- A label keeps a version out of retention; null removes it.
create or replace function "better_supabase"."label_version"(version_id uuid, label text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "subject_type", "subject_id" into v_tenant, v_subject_type, v_subject_id
    from "better_supabase"."versions" where "id" = label_version.version_id;
  if v_subject_type is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'versions.create'), false) and case v_subject_type
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_subject_id)::uuid and s."organization_id" = v_tenant)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    else false
  end and v_subject_type <> 'ai_document')) then
    raise exception 'not allowed to label this version' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  update "better_supabase"."versions" set "label" = nullif(trim(label_version.label), '')
    where "id" = label_version.version_id and not "frozen";
  if not found then
    raise exception 'a frozen version keeps its label' using errcode = '55000', hint = 'VERSION_FROZEN';
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."label_version"(uuid, text) from public, anon;
grant execute on function "better_supabase"."label_version"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_version"(version_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_number integer;
  v_frozen boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "subject_type", "subject_id", "number", "frozen"
    into v_tenant, v_subject_type, v_subject_id, v_number, v_frozen
    from "better_supabase"."versions" where "id" = delete_version.version_id;
  if v_subject_type is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'versions.manage'), false) and v_subject_type <> 'ai_document')) then
    raise exception 'not allowed to delete versions' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  if v_frozen then
    raise exception 'a frozen version can''t be deleted' using errcode = '55000', hint = 'VERSION_FROZEN';
  end if;
  delete from "better_supabase"."versions" where "id" = delete_version.version_id;
  perform "better_supabase".emit_event('version.deleted', jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', delete_version.version_id, 'number', v_number), 'versions/' || delete_version.version_id::text, (v_tenant)::text, null, 'better-supabase/versions');
  perform better_supabase.audit_event(
    event_type => 'version.deleted',
    category => 'data',
    target_type => 'version',
    record_id => delete_version.version_id::text,
    summary => 'deleted version ' || v_number::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', delete_version.version_id, 'number', v_number)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_version"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_version"(uuid) to authenticated, service_role;

-- on.<type>.auto and .freeze: tg_argv is the subject type, its
-- id and tenant columns, the snapshot columns, then the freeze column and
-- values (empty for auto). A restore sets better_supabase.restoring_version, so it isn't
-- snapshotted twice.
create or replace function "better_supabase"."versions_capture"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_columns text[] := string_to_array(tg_argv[3], ',');
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_content jsonb;
  v_previous jsonb;
  v_label text;
begin
  if coalesce(current_setting('better_supabase.restoring_version', true), '') = 'on' then
    return null;
  end if;
  select jsonb_object_agg(e.key, e.value) into v_content from jsonb_each(v_new) e where e.key = any (v_columns);
  if tg_argv[4] = '' then
    if v_old is not null then
      select jsonb_object_agg(e.key, e.value) into v_previous from jsonb_each(v_old) e where e.key = any (v_columns);
      if v_previous is not distinct from v_content then
        return null;
      end if;
    end if;
    perform "better_supabase"."version_insert"((v_new ->> tg_argv[2])::uuid, tg_argv[0], v_new ->> tg_argv[1], v_content, null, null, 'auto', false, auth.uid());
  else
    v_label := v_new ->> tg_argv[4];
    if v_label = any (string_to_array(tg_argv[5], ',')) and (v_old is null or (v_old ->> tg_argv[4]) is distinct from v_label) then
      perform "better_supabase"."version_insert"((v_new ->> tg_argv[2])::uuid, tg_argv[0], v_new ->> tg_argv[1], v_content, null, v_label, 'auto', true, auth.uid());
    end if;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."versions_capture"() from public, anon, authenticated;
create trigger "bsb_versions_project_auto"
  after insert or update of "name", "budget_minor", "currency" on "public"."projects"
  for each row execute function "better_supabase"."versions_capture"('project', 'id', 'organization_id', 'name,budget_minor,currency', '', '');

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('versions.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.versions deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"version","event_prefix":"version"}');

-- blocks.versions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."version_insert"(tenant uuid, subject_type text, subject_id text, content jsonb, storage_path text, label text, source text, frozen boolean, actor uuid, file_sha256 text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."version_insert"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) from public, anon, authenticated;
grant execute on function "api"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) to service_role;

create or replace function "api"."snapshot_version"(tenant uuid, subject_type text, subject_id text, content jsonb default null, label text default null, storage_path text default null, file_sha256 text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."snapshot_version"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."snapshot_version"(uuid, text, text, jsonb, text, text, text) from public, anon;
grant execute on function "api"."snapshot_version"(uuid, text, text, jsonb, text, text, text) to authenticated, service_role;

create or replace function "api"."list_versions"(tenant uuid, subject_type text, subject_id text, page_size integer default 50, before integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_versions"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_versions"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "api"."list_versions"(uuid, text, text, integer, integer) to authenticated, service_role;

create or replace function "api"."get_version"(version_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_version"($1) $$;
revoke execute on function "api"."get_version"(uuid) from public, anon;
grant execute on function "api"."get_version"(uuid) to authenticated, service_role;

create or replace function "api"."get_versions"(version_ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_versions"($1) $$;
revoke execute on function "api"."get_versions"(uuid[]) from public, anon;
grant execute on function "api"."get_versions"(uuid[]) to authenticated, service_role;

create or replace function "api"."get_shared_version"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_shared_version"($1) $$;
revoke execute on function "api"."get_shared_version"(text) from public;
grant execute on function "api"."get_shared_version"(text) to anon, authenticated, service_role;

create or replace function "api"."restore_version"(version_id uuid, fields text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_version"($1, $2) $$;
revoke execute on function "api"."restore_version"(uuid, text[]) from public, anon;
grant execute on function "api"."restore_version"(uuid, text[]) to authenticated, service_role;

create or replace function "api"."label_version"(version_id uuid, label text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."label_version"($1, $2) $$;
revoke execute on function "api"."label_version"(uuid, text) from public, anon;
grant execute on function "api"."label_version"(uuid, text) to authenticated, service_role;

create or replace function "api"."delete_version"(version_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_version"($1) $$;
revoke execute on function "api"."delete_version"(uuid) from public, anon;
grant execute on function "api"."delete_version"(uuid) to authenticated, service_role;
