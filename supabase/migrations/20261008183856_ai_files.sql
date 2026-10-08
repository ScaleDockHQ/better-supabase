SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."ai_document_versions" (
  "document_id"           uuid                     NOT NULL,
  "version"               integer                  NOT NULL,
  "content"               text,
  "storage_path"          text,
  "created_by_message_id" text,
  "created_by"            uuid,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_document_versions_check" CHECK (((content IS NOT NULL) OR (storage_path IS NOT NULL))),
  CONSTRAINT "ai_document_versions_pkey" PRIMARY KEY (document_id, VERSION),
  CONSTRAINT "ai_document_versions_version_check" CHECK ((version >= 1))
);

ALTER TABLE "better_supabase"."ai_document_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_documents" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "owner_id"        uuid                     NOT NULL,
  "chat_id"         uuid,
  "kind"            text                     NOT NULL,
  "title"           text                     NOT NULL,
  "current_version" integer                  NOT NULL DEFAULT 1,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_documents_current_version_check" CHECK ((current_version >= 1)),
  CONSTRAINT "ai_documents_kind_check" CHECK ((kind = ANY (ARRAY['text'::text, 'code'::text, 'sheet'::text, 'image'::text]))),
  CONSTRAINT "ai_documents_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_documents_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 500)))
);

ALTER TABLE "better_supabase"."ai_documents"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_files" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "owner_id"        uuid                     NOT NULL,
  "chat_id"         uuid,
  "project_id"      uuid,
  "bucket"          text                     NOT NULL,
  "filename"        text                     NOT NULL,
  "media_type"      text                     NOT NULL,
  "byte_size"       bigint                   NOT NULL,
  "sha256"          text,
  "status"          text                     NOT NULL DEFAULT 'pending'::text,
  "source"          text                     NOT NULL DEFAULT 'upload'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "uploaded_at"     timestamp with time zone,
  "expires_at"      timestamp with time zone,
  CONSTRAINT "ai_files_byte_size_check" CHECK (((byte_size >= 0) AND (byte_size <= 52428800))),
  CONSTRAINT "ai_files_filename_check"
    CHECK ((((length(filename) >= 1) AND (length(filename) <= 255)) AND (filename !~ '[/\\]'::text) AND (filename <> ALL (ARRAY['.'::text, '..'::text])))),
  CONSTRAINT "ai_files_media_type_check" CHECK ((media_type ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'::text)),
  CONSTRAINT "ai_files_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_files_sha256_check" CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "ai_files_source_check" CHECK ((source = ANY (ARRAY['upload'::text, 'generated'::text, 'provider'::text]))),
  CONSTRAINT "ai_files_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'ready'::text, 'failed'::text])))
);

ALTER TABLE "better_supabase"."ai_files"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_provider_files" (
  "file_id"    uuid                     NOT NULL,
  "provider"   text                     NOT NULL,
  "reference"  text                     NOT NULL,
  "expires_at" timestamp with time zone,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_provider_files_pkey" PRIMARY KEY (file_id, PROVIDER),
  CONSTRAINT "ai_provider_files_provider_check" CHECK (((length(provider) >= 1) AND (length(provider) <= 100))),
  CONSTRAINT "ai_provider_files_reference_check" CHECK (((length(reference) >= 1) AND (length(reference) <= 2000)))
);

ALTER TABLE "better_supabase"."ai_provider_files"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_suggestions" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "document_id"    uuid                     NOT NULL,
  "version"        integer                  NOT NULL,
  "original_text"  text                     NOT NULL,
  "suggested_text" text                     NOT NULL,
  "description"    text,
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "resolved_at"    timestamp with time zone,
  "accepted"       boolean,
  CONSTRAINT "ai_suggestions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."ai_suggestions"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."ai_files"
  ADD COLUMN "path" text GENERATED ALWAYS AS ((((((((organization_id)::text || '/'::text) || (owner_id)::text) || '/'::text) || (id)::text) || '/'::text) || filename)) STORED;

CREATE OR REPLACE FUNCTION api.confirm_ai_file (
  file_id uuid,
  sha256  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."confirm_ai_file"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_ai_document (
  tenant       uuid,
  kind         text,
  title        text,
  content      text DEFAULT NULL::text,
  chat_id      uuid DEFAULT NULL::uuid,
  message_id   text DEFAULT NULL::text,
  owner        uuid DEFAULT NULL::uuid,
  storage_path text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_ai_document"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_document"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_file"($1) $function$;

CREATE OR REPLACE FUNCTION api.expiring_ai_provider_files (
  horizon interval DEFAULT '1 day'::interval,
  batch   integer  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."expiring_ai_provider_files"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_document"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_file"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_file_by_path (
  bucket text,
  path   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_file_by_path"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_provider_file (
  file_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_provider_file"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_document_versions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_files (
  chat_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_files"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_suggestions (
  document_id uuid,
  open_only   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_suggestions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_ai_files (
  older_than interval DEFAULT '1 day'::interval,
  batch      integer  DEFAULT 500
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_ai_files"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.reserve_ai_file (
  tenant     uuid,
  filename   text,
  media_type text,
  byte_size  bigint,
  chat_id    uuid   DEFAULT NULL::uuid,
  project_id uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reserve_ai_file"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.resolve_ai_suggestion (
  suggestion_id uuid,
  accepted      boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_ai_suggestion"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rollback_ai_document (
  document_id uuid,
  version     integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rollback_ai_document"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_ai_provider_file (
  file_id    uuid,
  provider   text,
  reference  text,
  expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_ai_provider_file"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.store_ai_file (
  tenant     uuid,
  owner      uuid,
  filename   text,
  media_type text,
  byte_size  bigint,
  chat_id    uuid   DEFAULT NULL::uuid,
  source     text   DEFAULT 'generated'::text,
  sha256     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."store_ai_file"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.suggest_ai_document_edit (
  document_id    uuid,
  original_text  text,
  suggested_text text,
  description    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."suggest_ai_document_edit"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.update_ai_document (
  document_id      uuid,
  content          text    DEFAULT NULL::text,
  title            text    DEFAULT NULL::text,
  message_id       text    DEFAULT NULL::text,
  expected_version integer DEFAULT NULL::integer,
  storage_path     text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_ai_document"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_file_object_allowed (
  bucket text,
  path   text,
  action text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."ai_files" a
    where a."bucket" = ai_file_object_allowed.bucket and a."path" = ai_file_object_allowed.path
      and case ai_file_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."owner_id" = auth.uid()
        when 'select' then a."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'ai_chat.admin'), false) or (a."chat_id" is not null and "better_supabase"."ai_chat_can_read"(a."chat_id"))
        when 'delete' then a."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'ai_chat.admin'), false)
        else false
      end
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.confirm_ai_file (
  file_id uuid,
  sha256  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
  v_size bigint;
begin
  select * into v_row from "better_supabase"."ai_files" x where x."id" = confirm_ai_file.file_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid()) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  if v_row."status" <> 'pending' then
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
  end if;
  select (o.metadata ->> 'size')::bigint into v_size
  from storage.objects o where o.bucket_id = v_row."bucket" and o.name = v_row."path";
  if not found then
    raise exception 'file % has no uploaded object yet', file_id using errcode = 'P0001', hint = 'AI_FILE_NOT_UPLOADED';
  end if;
  update "better_supabase"."ai_files" x set
    "status" = 'ready',
    "uploaded_at" = now(),
    "byte_size" = coalesce(v_size, x."byte_size"),
    "sha256" = coalesce(lower(confirm_ai_file.sha256), x."sha256")
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ai_document (
  tenant       uuid,
  kind         text,
  title        text,
  content      text DEFAULT NULL::text,
  chat_id      uuid DEFAULT NULL::uuid,
  message_id   text DEFAULT NULL::text,
  owner        uuid DEFAULT NULL::uuid,
  storage_path text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_ai_document.owner else auth.uid() end;
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  if v_owner is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_document.tenant, 'ai_chat.create'), false)) then
    raise exception 'you may not create documents here' using errcode = '42501', hint = 'AI_DOCUMENT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_documents" ("organization_id", "owner_id", "chat_id", "kind", "title")
  values (create_ai_document.tenant, v_owner, create_ai_document.chat_id, create_ai_document.kind, create_ai_document.title)
  returning * into v_row;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", 1, create_ai_document.content, create_ai_document.storage_path, create_ai_document.message_id, v_owner);
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = delete_ai_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_documents" x where x."id" = v_row."id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_files" x where x."id" = delete_ai_file.file_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_files" x where x."id" = v_row."id";
  return jsonb_build_object('bucket', v_row."bucket", 'path', v_row."path");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expiring_ai_provider_files (
  horizon interval DEFAULT '1 day'::interval,
  batch   integer  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('file_id', p."file_id", 'provider', p."provider", 'reference', p."reference", 'expires_at', p."expires_at")), '[]'::jsonb)
  from (
    select * from "better_supabase"."ai_provider_files"
    where "expires_at" is not null and "expires_at" <= now() + coalesce(horizon, interval '1 day')
    order by "expires_at"
    limit greatest(coalesce(batch, 100), 1)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'kind', x."kind", 'title', x."title", 'current_version', x."current_version", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('content', vv."content", 'storage_path', vv."storage_path")
  from "better_supabase"."ai_documents" x
  join "better_supabase"."ai_document_versions" vv on vv."document_id" = x."id" and vv."version" = x."current_version"
  where x."id" = get_ai_document.document_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") from "better_supabase"."ai_files" x where x."id" = get_ai_file.file_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_file_by_path (
  bucket text,
  path   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") from "better_supabase"."ai_files" x
  where x."bucket" = get_ai_file_by_path.bucket and x."path" = get_ai_file_by_path.path
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_provider_file (
  file_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('file_id', p."file_id", 'provider', p."provider", 'reference', p."reference", 'expires_at', p."expires_at")
  from "better_supabase"."ai_provider_files" p
  where p."file_id" = get_ai_provider_file.file_id and p."provider" = get_ai_provider_file.provider
    and (p."expires_at" is null or p."expires_at" > now())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('document_id', x."document_id", 'version', x."version", 'content', x."content", 'storage_path', x."storage_path", 'created_by_message_id', x."created_by_message_id", 'created_by', x."created_by", 'created_at', x."created_at") order by x."version" desc), '[]'::jsonb)
  from "better_supabase"."ai_document_versions" x where x."document_id" = list_ai_document_versions.document_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_files (
  chat_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."ai_files" x where x."chat_id" = list_ai_files.chat_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_suggestions (
  document_id uuid,
  open_only   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'document_id', x."document_id", 'version', x."version", 'original_text', x."original_text", 'suggested_text', x."suggested_text", 'description', x."description", 'created_by', x."created_by", 'created_at', x."created_at", 'resolved_at', x."resolved_at", 'accepted', x."accepted") order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."ai_suggestions" x
  where x."document_id" = list_ai_suggestions.document_id
    and (not coalesce(open_only, true) or x."resolved_at" is null)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_ai_files (
  older_than interval DEFAULT '1 day'::interval,
  batch      integer  DEFAULT 500
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_removed jsonb;
begin
  with doomed as (
    select x."id" from "better_supabase"."ai_files" x
    where (x."status" = 'pending' and x."created_at" <= now() - coalesce(older_than, interval '1 day'))
      or x."expires_at" <= now()
      or (x."chat_id" is not null and not exists (select 1 from "better_supabase"."ai_chats" ch where ch."id" = x."chat_id"))
    limit greatest(coalesce(batch, 500), 1)
  ),
  gone as (
    delete from "better_supabase"."ai_files" x using doomed where x."id" = doomed."id"
    returning x."bucket" as bucket, x."path" as path
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', gone.bucket, 'path', gone.path)), '[]'::jsonb) into v_removed from gone;
  return v_removed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reserve_ai_file (
  tenant     uuid,
  filename   text,
  media_type text,
  byte_size  bigint,
  chat_id    uuid   DEFAULT NULL::uuid,
  project_id uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', reserve_ai_file.tenant, 'ai_chat.create'), false) then
    raise exception 'you may not upload files here' using errcode = '42501', hint = 'AI_FILE_FORBIDDEN';
  end if;
  if byte_size < 0 or byte_size > 52428800 then
    raise exception 'files are limited to % bytes', 52428800 using errcode = '22023', hint = 'AI_FILE_TOO_LARGE';
  end if;
  insert into "better_supabase"."ai_files" ("organization_id", "owner_id", "chat_id", "project_id", "bucket", "filename", "media_type", "byte_size")
  values (reserve_ai_file.tenant, auth.uid(), reserve_ai_file.chat_id, reserve_ai_file.project_id, 'ai-files', reserve_ai_file.filename, lower(reserve_ai_file.media_type), reserve_ai_file.byte_size)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_ai_suggestion (
  suggestion_id uuid,
  accepted      boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_suggestions"%rowtype;
  v_doc "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_suggestions" x where x."id" = resolve_ai_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."ai_documents" x where x."id" = v_row."document_id";
  end if;
  if v_doc."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_doc."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'suggestion % not found', suggestion_id using errcode = 'P0002', hint = 'AI_SUGGESTION_NOT_FOUND';
  end if;
  update "better_supabase"."ai_suggestions" x set "resolved_at" = now(), "accepted" = resolve_ai_suggestion.accepted
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rollback_ai_document (
  document_id uuid,
  version     integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
  v_old "better_supabase"."ai_document_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = rollback_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."ai_document_versions" x where x."document_id" = v_row."id" and x."version" = rollback_ai_document.version;
  if not found then
    raise exception 'document % has no version %', document_id, rollback_ai_document.version using errcode = 'P0002', hint = 'AI_DOCUMENT_VERSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, v_old."content", v_old."storage_path", null, auth.uid());
  update "better_supabase"."ai_documents" x set "current_version" = v_row."current_version" + 1, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ai_provider_file (
  file_id    uuid,
  provider   text,
  reference  text,
  expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."ai_provider_files" ("file_id", "provider", "reference", "expires_at")
  values (set_ai_provider_file.file_id, set_ai_provider_file.provider, set_ai_provider_file.reference, set_ai_provider_file.expires_at)
  on conflict ("file_id", "provider") do update
    set "reference" = excluded."reference", "expires_at" = excluded."expires_at", "created_at" = now()
  returning true
$function$;

CREATE OR REPLACE FUNCTION better_supabase.store_ai_file (
  tenant     uuid,
  owner      uuid,
  filename   text,
  media_type text,
  byte_size  bigint,
  chat_id    uuid   DEFAULT NULL::uuid,
  source     text   DEFAULT 'generated'::text,
  sha256     text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  insert into "better_supabase"."ai_files" ("organization_id", "owner_id", "chat_id", "bucket", "filename", "media_type", "byte_size", "status", "source", "sha256", "uploaded_at")
  values (store_ai_file.tenant, store_ai_file.owner, store_ai_file.chat_id, 'ai-files', store_ai_file.filename, lower(store_ai_file.media_type), store_ai_file.byte_size, 'ready', coalesce(store_ai_file.source, 'generated'), lower(store_ai_file.sha256), now())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.suggest_ai_document_edit (
  document_id    uuid,
  original_text  text,
  suggested_text text,
  description    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_doc "better_supabase"."ai_documents"%rowtype;
  v_row "better_supabase"."ai_suggestions"%rowtype;
begin
  select * into v_doc from "better_supabase"."ai_documents" x where x."id" = suggest_ai_document_edit.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_doc."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai_chat.admin'), false) or (v_doc."chat_id" is not null and "better_supabase"."ai_chat_can_read"(v_doc."chat_id")))) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_suggestions" ("document_id", "version", "original_text", "suggested_text", "description", "created_by")
  values (v_doc."id", v_doc."current_version", suggest_ai_document_edit.original_text, suggest_ai_document_edit.suggested_text, suggest_ai_document_edit.description, auth.uid())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ai_document (
  document_id      uuid,
  content          text    DEFAULT NULL::text,
  title            text    DEFAULT NULL::text,
  message_id       text    DEFAULT NULL::text,
  expected_version integer DEFAULT NULL::integer,
  storage_path     text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = update_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  if expected_version is not null and expected_version <> v_row."current_version" then
    raise exception 'document % is at version %', document_id, v_row."current_version" using errcode = '40001', hint = 'AI_DOCUMENT_CONFLICT';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, update_ai_document.content, update_ai_document.storage_path, update_ai_document.message_id, auth.uid());
  update "better_supabase"."ai_documents" x set
    "current_version" = v_row."current_version" + 1,
    "title" = coalesce(update_ai_document.title, x."title"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."ai_document_versions"
  ADD CONSTRAINT "ai_document_versions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_documents"
  ADD CONSTRAINT "ai_documents_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_document_versions"
  ADD CONSTRAINT "ai_document_versions_document_id_fkey" FOREIGN KEY (document_id) REFERENCES better_supabase.ai_documents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_files"
  ADD CONSTRAINT "ai_files_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_provider_files"
  ADD CONSTRAINT "ai_provider_files_file_id_fkey" FOREIGN KEY (file_id) REFERENCES better_supabase.ai_files(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_suggestions"
  ADD CONSTRAINT "ai_suggestions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_suggestions"
  ADD CONSTRAINT "ai_suggestions_document_id_fkey" FOREIGN KEY (document_id) REFERENCES better_supabase.ai_documents(id) ON DELETE CASCADE;

CREATE INDEX ai_document_versions_created_by_idx ON better_supabase.ai_document_versions USING btree (created_by)
  WHERE (created_by IS NOT NULL);

CREATE INDEX ai_documents_chat_idx ON better_supabase.ai_documents USING btree (chat_id)
  WHERE (chat_id IS NOT NULL);

CREATE INDEX ai_documents_owner_idx ON better_supabase.ai_documents USING btree (owner_id);

CREATE INDEX ai_documents_tenant_idx ON better_supabase.ai_documents USING btree (organization_id);

CREATE INDEX ai_files_chat_idx ON better_supabase.ai_files USING btree (chat_id)
  WHERE (chat_id IS NOT NULL);

CREATE UNIQUE INDEX ai_files_object_idx ON better_supabase.ai_files USING btree (bucket, path);

CREATE INDEX ai_files_owner_idx ON better_supabase.ai_files USING btree (owner_id);

CREATE INDEX ai_files_pending_idx ON better_supabase.ai_files USING btree (created_at)
  WHERE (status = 'pending'::text);

CREATE INDEX ai_files_tenant_idx ON better_supabase.ai_files USING btree (organization_id);

CREATE INDEX ai_provider_files_expires_idx ON better_supabase.ai_provider_files USING btree (expires_at)
  WHERE (expires_at IS NOT NULL);

CREATE INDEX ai_suggestions_created_by_idx ON better_supabase.ai_suggestions USING btree (created_by)
  WHERE (created_by IS NOT NULL);

CREATE INDEX ai_suggestions_document_idx ON better_supabase.ai_suggestions USING btree (document_id);

CREATE POLICY "ai_document_versions_read" ON "better_supabase"."ai_document_versions"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.ai_documents doc
  WHERE (doc.id = ai_document_versions.document_id))));

CREATE POLICY "ai_documents_read" ON "better_supabase"."ai_documents"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with)) OR ((chat_id IS
    NOT NULL) AND better_supabase.ai_chat_can_read(chat_id))));

CREATE POLICY "ai_files_read" ON "better_supabase"."ai_files"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with)) OR ((chat_id IS
    NOT NULL) AND better_supabase.ai_chat_can_read(chat_id))));

CREATE POLICY "ai_suggestions_read" ON "better_supabase"."ai_suggestions"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.ai_documents doc
  WHERE (doc.id = ai_suggestions.document_id))));

CREATE POLICY "bs_ai_files_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'delete'::text)));

CREATE POLICY "bs_ai_files_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'insert'::text)));

CREATE POLICY "bs_ai_files_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'select'::text)));

REVOKE ALL ON FUNCTION "api"."confirm_ai_file"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."confirm_ai_file"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_file"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_file"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."expiring_ai_provider_files"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."expiring_ai_provider_files"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_file"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_file"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_file_by_path"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_file_by_path"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_provider_file"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_provider_file"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_document_versions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_document_versions"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_files"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_files"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_suggestions"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_suggestions"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_ai_files"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_ai_files"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_ai_suggestion"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_ai_suggestion"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rollback_ai_document"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rollback_ai_document"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_ai_provider_file"(uuid, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_ai_provider_file"(uuid, text, text, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."suggest_ai_document_edit"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."suggest_ai_document_edit"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_ai_document"(uuid, text, text, text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_ai_document"(uuid, text, text, text, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_file_object_allowed"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_file_object_allowed"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."confirm_ai_file"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."confirm_ai_file"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_file"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_file"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."expiring_ai_provider_files"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."expiring_ai_provider_files"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_document"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_document"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_file"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_file"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_file_by_path"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_file_by_path"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_provider_file"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_provider_file"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_document_versions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_document_versions"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_files"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_files"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_suggestions"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_suggestions"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_ai_files"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_ai_files"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_ai_suggestion"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_ai_suggestion"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rollback_ai_document"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rollback_ai_document"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_ai_provider_file"(uuid, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_ai_provider_file"(uuid, text, text, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."suggest_ai_document_edit"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."suggest_ai_document_edit"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_ai_document"(uuid, text, text, text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_ai_document"(uuid, text, text, text, integer, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_document_versions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_document_versions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_documents" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_documents" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_files" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_files" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_provider_files" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_suggestions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_suggestions" TO "service_role";
