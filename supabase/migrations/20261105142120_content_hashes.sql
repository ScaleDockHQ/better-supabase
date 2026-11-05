SET local check_function_bodies = off;

DROP FUNCTION "api"."set_attachment_status"(uuid, text, text);

DROP FUNCTION "api"."snapshot_version"(uuid, text, text, jsonb, text, text);

DROP FUNCTION "api"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid);

DROP FUNCTION "better_supabase"."snapshot_version"(uuid, text, text, jsonb, text, text);

DROP FUNCTION "better_supabase"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid);

ALTER TABLE "better_supabase"."attachment_versions"
  ADD COLUMN "sha256" text;

ALTER TABLE "better_supabase"."attachment_versions"
  ADD COLUMN "hash_verified_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."attachments"
  ADD COLUMN "sha256" text;

ALTER TABLE "better_supabase"."attachments"
  ADD COLUMN "hash_verified_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."versions"
  ADD COLUMN "file_hash" text;

ALTER TABLE "better_supabase"."versions"
  ADD COLUMN "hash_version" smallint NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION api.set_attachment_status (
  id     uuid,
  status text,
  detail text DEFAULT NULL::text,
  sha256 text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_attachment_status"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.snapshot_version (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  content      jsonb DEFAULT NULL::jsonb,
  label        text  DEFAULT NULL::text,
  storage_path text  DEFAULT NULL::text,
  file_sha256  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."snapshot_version"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.version_insert (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  content      jsonb,
  storage_path text,
  label        text,
  source       text,
  frozen       boolean,
  actor        uuid,
  file_sha256  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."version_insert"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shared_version (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_version (
  version_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_versions (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50,
  before       integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replace_attachment (
  id        uuid,
  name      text,
  mime_type text,
  size      bigint,
  width     integer DEFAULT NULL::integer,
  height    integer DEFAULT NULL::integer,
  pages     integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and (coalesce(better_supabase.can('tenant', v_row."organization_id", case v_row."subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' when 'expense_line' then 'expenses.submit' else 'attachments.upload' end), false) or ((v_row."organization_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at", "sha256", "hash_verified_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at", v_row."sha256", v_row."hash_verified_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "better_supabase"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "better_supabase"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null,
    "sha256" = null,
    "hash_verified_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.replaced', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.replaced',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'version', v_row."version")
  );
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_attachment_version (
  id      uuid,
  version integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_old "better_supabase"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and (coalesce(better_supabase.can('tenant', v_row."organization_id", case v_row."subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' when 'expense_line' then 'expenses.submit' else 'attachments.upload' end), false) or ((v_row."organization_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "better_supabase"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at", "sha256", "hash_verified_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at", v_row."sha256", v_row."hash_verified_at");
  end if;
  update "better_supabase"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = v_old."status",
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at",
    "sha256" = v_old."sha256",
    "hash_verified_at" = v_old."hash_verified_at"
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.restored', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.restored',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'version', v_row."version")
  );
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_attachment_status (
  id     uuid,
  status text,
  detail text DEFAULT NULL::text,
  sha256 text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."attachments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_attachment_status.status not in ('clean', 'infected', 'failed') then
    raise exception 'status must be clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  if set_attachment_status.sha256 is not null and set_attachment_status.sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'sha256 must be 64 lowercase hex characters' using errcode = '22023', hint = 'ATTACHMENT_HASH_INVALID';
  end if;
  update "better_supabase"."attachments" a set
    "status" = set_attachment_status.status,
    "scan_detail" = set_attachment_status.detail,
    "scanned_at" = now(),
    "sha256" = coalesce(set_attachment_status.sha256, a."sha256"),
    "hash_verified_at" = case when set_attachment_status.sha256 is null then a."hash_verified_at" else now() end
  where a."id" = set_attachment_status.id
    and a."uploaded_at" is not null
    and a."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."attachments" a where a."id" = set_attachment_status.id;
    return case when v_row."id" is null then null else (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end))) end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  perform "better_supabase".emit_event('attachment.scanned', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'status', v_row."status", 'uploadedBy', v_row."uploaded_by"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, 'attachment.scanned:' || v_row."id"::text || ':' || v_row."status", 'better-supabase/attachments');
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_signature (
  request_id          uuid,
  method              text,
  typed_name          text DEFAULT NULL::text,
  image_attachment_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req "better_supabase"."signature_requests"%rowtype;
  v_row "better_supabase"."signatures"%rowtype;
  v_typed text := nullif(trim(sign_signature.typed_name), '');
  v_current text;
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to sign' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if sign_signature.method not in ('drawn', 'typed', 'click') then
    raise exception 'method must be drawn, typed or click' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'typed' and v_typed is null then
    raise exception 'a typed signature needs the typed name' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'drawn' and sign_signature.image_attachment_id is null then
    raise exception 'a drawn signature needs its image attachment' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = sign_signature.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  if exists (select 1 from "better_supabase"."signatures" g where g."request_id" = v_req."id" and g."signer" = v_me) then
    raise exception 'you already signed this request' using errcode = '23505', hint = 'SIGNATURE_ALREADY_SIGNED';
  end if;
  select count(*) into v_count from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  if v_req."sign_order" = 'sequential' and array_position(v_req."signers", v_me) <> v_count + 1 then
    raise exception 'an earlier signer hasn''t signed yet' using errcode = '55000', hint = 'SIGNATURE_OUT_OF_ORDER';
  end if;
  if sign_signature.image_attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = sign_signature.image_attachment_id
      and a."organization_id" = v_req."tenant_id"
  ) then
    raise exception 'the signature image isn''t an attachment in this organization' using errcode = '22023', hint = 'SIGNATURE_IMAGE_NOT_FOUND';
  end if;
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  if v_current is distinct from v_req."content_hash" then
    raise exception 'the version to sign changed after the request was made' using errcode = '55000', hint = 'SIGNATURE_CONTENT_CHANGED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_sign"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using v_req."id", v_me, sign_signature.method;
    end if;
  end;
  insert into "better_supabase"."signatures" ("request_id", "tenant_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."tenant_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    encode(extensions.digest(v_req."id"::text || ':' || v_req."content_hash" || ':' || v_me::text || ':' || sign_signature.method || ':' || coalesce(v_typed, '') || ':' || coalesce(sign_signature.image_attachment_id::text, '') || ':' || to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex'),
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  perform "better_supabase".emit_event('signature_request.signed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.signed',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'signed ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method")
  );
  -- A signer who approves the linked request's current step decides it.
  if v_req."approval_request_id" is not null and "better_supabase"."approval_eligible"(v_req."approval_request_id") then
    perform "better_supabase"."decide_approval"(v_req."approval_request_id", 'approved', 'Signed electronically');
  end if;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "better_supabase"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
      where x."id" = v_req."id"
      returning * into v_req;
    perform "better_supabase".emit_event('signature_request.completed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'versionId', v_req."version_id", 'meaning', v_req."meaning"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_sign"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'requestId', v_row."request_id", 'signer', v_row."signer", 'method', v_row."method", 'typedName', v_row."typed_name", 'imageAttachmentId', v_row."image_attachment_id", 'signedHash', v_row."signed_hash", 'ip', v_row."ip", 'userAgent', v_row."user_agent", 'signedAt', v_row."signed_at") || jsonb_build_object('requestStatus', v_req."status");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.signature_verification (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_req_hash text;
  v_current text;
  v_latest uuid;
  v_latest_hash text;
  v_items jsonb;
  v_signed boolean;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = signature_verification.request_id;
  if not found then
    return null;
  end if;
  v_req_hash := v_req."content_hash";
  select case when x."file_hash" is null then encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') else encode(extensions.digest(coalesce(x."content"::text, '') || x."file_hash", 'sha256'), 'hex') end into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  select x."id", x."content_hash" into v_latest, v_latest_hash
    from "better_supabase"."versions" x
    where x."subject_type" = v_req."subject_type" and x."subject_id" = v_req."subject_id"
    order by x."number" desc
    limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'signer', g."signer", 'valid', g."signed_hash" = encode(extensions.digest(g."request_id"::text || ':' || v_req_hash || ':' || g."signer"::text || ':' || g."method" || ':' || coalesce(g."typed_name", '') || ':' || coalesce(g."image_attachment_id"::text, '') || ':' || to_char(g."signed_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex')) order by g."signed_at"), '[]'::jsonb)
    into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  select coalesce(bool_and((i ->> 'valid')::boolean), true) into v_signed from jsonb_array_elements(v_items) i;
  return jsonb_build_object(
    'valid', v_current is not distinct from v_req_hash and v_signed,
    'contentMatches', v_current is not distinct from v_req_hash,
    'changedSince', v_latest_hash is distinct from v_req_hash,
    'latestVersionId', v_latest,
    'signatures', v_items
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.snapshot_version (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  content      jsonb DEFAULT NULL::jsonb,
  label        text  DEFAULT NULL::text,
  storage_path text  DEFAULT NULL::text,
  file_sha256  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.version_insert (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  content      jsonb,
  storage_path text,
  label        text,
  source       text,
  frozen       boolean,
  actor        uuid,
  file_sha256  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "attachments_sha256_check" CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text));

ALTER TABLE "better_supabase"."versions"
  ADD CONSTRAINT "versions_file_hash_check" CHECK ((file_hash ~ '^[0-9a-f]{64}$'::text));

ALTER TABLE "better_supabase"."versions"
  ADD CONSTRAINT "versions_hash_version_check" CHECK ((hash_version = ANY (ARRAY[1, 2])));

REVOKE ALL ON FUNCTION "api"."set_attachment_status"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_attachment_status"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."snapshot_version"(uuid, text, text, jsonb, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."snapshot_version"(uuid, text, text, jsonb, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_attachment_status"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_attachment_status"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."snapshot_version"(uuid, text, text, jsonb, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."snapshot_version"(uuid, text, text, jsonb, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."version_insert"(uuid, text, text, jsonb, text, text, text, boolean, uuid, text) TO "service_role";

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 9, 'managed'), ('versions', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
