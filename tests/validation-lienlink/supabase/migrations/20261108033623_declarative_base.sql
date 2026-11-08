SET local check_function_bodies = off;

CREATE SCHEMA "better_supabase";

CREATE TABLE "better_supabase"."attachment_document_types" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "key"        text                     NOT NULL,
  "name"       text                     NOT NULL,
  "fields"     jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "attachment_document_types_pkey" PRIMARY KEY (id),
  CONSTRAINT "attachment_document_types_tenant_id_key_key" UNIQUE (tenant_id, key),
  CONSTRAINT "bsb_attachment_document_types_fields_check" CHECK ((jsonb_typeof(fields) = 'object'::text)),
  CONSTRAINT "bsb_attachment_document_types_key_check" CHECK ((key ~ '^[a-z][a-z0-9_.-]{0,62}$'::text)),
  CONSTRAINT "bsb_attachment_document_types_name_check" CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 200)))
);

ALTER TABLE "better_supabase"."attachment_document_types"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."attachment_versions" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "attachment_id"    uuid                     NOT NULL,
  "version"          integer                  NOT NULL,
  "bucket"           text                     NOT NULL,
  "object_path"      text                     NOT NULL,
  "name"             text                     NOT NULL,
  "mime_type"        text                     NOT NULL,
  "size"             bigint                   NOT NULL,
  "width"            integer,
  "height"           integer,
  "pages"            integer,
  "status"           text                     NOT NULL,
  "scan_detail"      text,
  "uploaded_by"      uuid,
  "uploaded_at"      timestamp with time zone,
  "scanned_at"       timestamp with time zone,
  "sha256"           text,
  "hash_verified_at" timestamp with time zone,
  "archived_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "attachment_versions_attachment_id_version_key" UNIQUE (attachment_id, VERSION),
  CONSTRAINT "attachment_versions_bucket_object_path_key" UNIQUE (bucket, object_path),
  CONSTRAINT "attachment_versions_pkey" PRIMARY KEY (id),
  CONSTRAINT "bsb_attachment_versions_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'clean'::text, 'infected'::text, 'failed'::text]))),
  CONSTRAINT "bsb_attachment_versions_version_check" CHECK ((version >= 1))
);

ALTER TABLE "better_supabase"."attachment_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."attachments" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "subject_type"     text,
  "subject_id"       text,
  "bucket"           text                     NOT NULL DEFAULT 'attachments'::text,
  "object_path"      text,
  "name"             text                     NOT NULL,
  "mime_type"        text                     NOT NULL,
  "size"             bigint                   NOT NULL,
  "status"           text                     NOT NULL DEFAULT 'pending'::text,
  "scan_detail"      text,
  "created_at"       timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "uploaded_at"      timestamp with time zone,
  "scanned_at"       timestamp with time zone,
  "version"          integer                  NOT NULL DEFAULT 1,
  "sha256"           text,
  "hash_verified_at" timestamp with time zone,
  "width"            integer,
  "height"           integer,
  "pages"            integer,
  "metadata"         jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "document_type_id" uuid,
  "source"           text,
  "external_id"      text,
  "storage_status"   text                     NOT NULL DEFAULT 'pending_upload'::text,
  "source_path"      text,
  "job_id"           uuid                     GENERATED ALWAYS AS (
CASE
    WHEN (subject_type = 'job'::text) THEN (subject_id)::uuid
    ELSE NULL::uuid
END) STORED,
  CONSTRAINT "attachments_pkey" PRIMARY KEY (id),
  CONSTRAINT "bsb_attachments_check" CHECK (((subject_type IS NULL) = (subject_id IS NULL))),
  CONSTRAINT "bsb_attachments_external_id_check" CHECK (((length(external_id) >= 1) AND (length(external_id) <= 500))),
  CONSTRAINT "bsb_attachments_external" CHECK (((source IS NULL) = (external_id IS NULL))),
  CONSTRAINT "bsb_attachments_height_check" CHECK ((height > 0)),
  CONSTRAINT "bsb_attachments_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "bsb_attachments_mime_type_check" CHECK ((mime_type ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'::text)),
  CONSTRAINT "bsb_attachments_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 255))),
  CONSTRAINT "bsb_attachments_pages_check" CHECK ((pages > 0)),
  CONSTRAINT "bsb_attachments_sha256_check" CHECK ((sha256 ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "bsb_attachments_size" CHECK (((size >= 0) AND (size <= 52428800))),
  CONSTRAINT "bsb_attachments_source_check" CHECK (((length(source) >= 1) AND (length(source) <= 200))),
  CONSTRAINT "bsb_attachments_source_path_check" CHECK (((length(source_path) >= 1) AND (length(source_path) <= 2000))),
  CONSTRAINT "bsb_attachments_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'clean'::text, 'infected'::text, 'failed'::text]))),
  CONSTRAINT "bsb_attachments_storage_status_check" CHECK ((storage_status = ANY (ARRAY['stored'::text, 'pending_upload'::text, 'missing'::text]))),
  CONSTRAINT "bsb_attachments_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200))),
  CONSTRAINT "bsb_attachments_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "bsb_attachments_version_check" CHECK ((version >= 1)),
  CONSTRAINT "bsb_attachments_width_check" CHECK ((width > 0)),
  "uploaded_by"      uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."attachments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."blocks" (
  "name"         text                     NOT NULL,
  "block"        text,
  "version"      integer                  NOT NULL,
  "mode"         text                     NOT NULL,
  "installed_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "blocks_pkey" PRIMARY KEY (name)
);

ALTER TABLE "better_supabase"."blocks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."memberships" (
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "role"            text                     NOT NULL DEFAULT 'member'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "last_used_at"    timestamp with time zone,
  "disabled_at"     timestamp with time zone,
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  CONSTRAINT "bsb_memberships_role_check" CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text, 'viewer'::text]))),
  CONSTRAINT "memberships_id_key" UNIQUE (id),
  CONSTRAINT "memberships_pkey" PRIMARY KEY (organization_id, user_id)
);

ALTER TABLE "better_supabase"."memberships"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."organizations" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "name"        text                     NOT NULL,
  "slug"        text                     NOT NULL,
  "created_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "disabled_at" timestamp with time zone,
  "deleted_at"  timestamp with time zone,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_organizations_name_check" CHECK ((length(btrim(name)) > 0)),
  CONSTRAINT "organizations_pkey" PRIMARY KEY (id),
  CONSTRAINT "organizations_slug_format" CHECK ((slug ~ '^[a-z0-9-]+$'::text))
);

ALTER TABLE "better_supabase"."organizations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."profiles" (
  "id"                     uuid                     NOT NULL,
  "email"                  text,
  "username"               text,
  "full_name"              text,
  "first_name"             text,
  "last_name"              text,
  "avatar_url"             text,
  "avatar_path"            text,
  "locale"                 text,
  "active_organization_id" uuid,
  "active_team_id"         uuid,
  "onboarding"             jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "disabled_at"            timestamp with time zone,
  "created_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"             timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_profiles_username_check"
    CHECK
    (((username IS NULL) OR ((length(username) >= 3) AND (length(username) <= 32) AND (username ~* '^[a-z][a-z0-9_]*$'::text) AND (lower(username) <> ALL (ARRAY['admin'::text,
    'administrator'::text,
    'api'::text,
    'app'::text,
    'auth'::text,
    'billing'::text,
    'help'::text, 'login'::text, 'logout'::text, 'me'::text, 'null'::text, 'root'::text, 'settings'::text, 'signup'::text, 'support'::text, 'system'::text, 'www'::text]))))),
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id),
  CONSTRAINT "profiles_username_format" CHECK (((username IS NULL) OR (username ~ '^[a-z0-9_]+$'::text)))
);

ALTER TABLE "better_supabase"."profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."scanned_objects" (
  "bucket"      text                     NOT NULL,
  "object_path" text                     NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'pending'::text,
  "scan_detail" text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "scanned_at"  timestamp with time zone,
  CONSTRAINT "bsb_scanned_objects_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'clean'::text, 'infected'::text, 'failed'::text]))),
  CONSTRAINT "scanned_objects_pkey" PRIMARY KEY (bucket, object_path)
);

ALTER TABLE "better_supabase"."scanned_objects"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."team_members" (
  "team_id"    uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "tenant_id"  uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "team_members_pkey" PRIMARY KEY (team_id, user_id)
);

ALTER TABLE "better_supabase"."team_members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."teams" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "name"        text                     NOT NULL,
  "slug"        text                     NOT NULL,
  "description" text,
  "status"      text                     NOT NULL DEFAULT 'active'::text,
  "created_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_teams_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "bsb_teams_slug_check" CHECK ((slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text)),
  CONSTRAINT "bsb_teams_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text]))),
  CONSTRAINT "teams_name_length" CHECK ((length(name) <= 80)),
  CONSTRAINT "teams_pkey" PRIMARY KEY (id),
  CONSTRAINT "teams_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "teams_tenant_id_slug_key" UNIQUE (tenant_id, slug)
);

ALTER TABLE "better_supabase"."teams"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."job_audit" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "job_id"          uuid                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "action"          text                     NOT NULL,
  "changed"         jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "job_audit_pkey" PRIMARY KEY (id),
  "actor"           uuid                     DEFAULT auth.uid()
);

ALTER TABLE "public"."job_audit"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."job_audit" FROM "anon";

CREATE TABLE "public"."jobs" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "team_id"         uuid,
  "title"           text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "jobs_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."jobs"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."jobs" FROM "anon";

CREATE TABLE "public"."user_signups" (
  "user_id"    uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "user_signups_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "public"."user_signups"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."user_signups" FROM "anon";

CREATE OR REPLACE FUNCTION better_supabase.acting_member()
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  header text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    return null;
  end if;
  header := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-bsb-actor';
  return case when header ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then header::uuid end;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.actor_may_write()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_team_member (
  team   uuid,
  member uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.allocate_username (
  base    text,
  user_id uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "better_supabase"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_team (
  team uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.as_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return value;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_authors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(y."id"::text, jsonb_build_object('id', pr."id", 'name', coalesce(nullif(pr."full_name", ''), nullif(trim(concat_ws(' ', pr."first_name", pr."last_name")), ''), pr."username"), 'avatarUrl', pr."avatar_url")), '{}'::jsonb)
  from "better_supabase"."attachments" y
  join "better_supabase"."profiles" pr on pr."id" = y."uploaded_by"
  where y."id" = any ($1)
    and y."tenant_id" in (select better_supabase.tenant_ids_with('attachments.read'))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_document_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new."storage_status" in ('stored', 'pending_upload') or new."uploaded_at" is not null then
    new."storage_status" := case when new."uploaded_at" is not null then 'stored' else
      case when new."storage_status" = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."tenant_id" is not null and exists (
      select 1 from "better_supabase"."attachments" x
      where x."tenant_id" = new."tenant_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "better_supabase"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."tenant_id" = new."tenant_id";
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
    v_error := "better_supabase"."attachment_fields_error"(v_fields, new."metadata");
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_FIELD_INVALID';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_fields_error (
  fields jsonb,
  data   jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_object_allowed (
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
    select 1 from "better_supabase"."attachments" a
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.read'), false))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        else false
      end
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_object_path()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  select "tenant_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_object_visible (
  bucket text,
  path   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."attachments" a
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_schema_error (
  fields jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachments_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."tenant_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."tenant_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.backfill_profiles()
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can (
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  COST 1000
  SET search_path TO ''
  AS $function$
  select case
    when can.scope = 'platform' then coalesce(better_supabase.platform_can(auth.uid(), can.permission), false)
    when can.scope in ('organization', 'tenant') then coalesce(better_supabase.member_can(auth.uid(), can.scope_id, can.permission), false)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_assign (
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role' or better_supabase.can_assign_as(auth.uid(), can_assign.tenant, can_assign.role)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_assign_as (
  member uuid,
  tenant uuid,
  role   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
        and not coalesce(better_supabase.member_can(can_assign_as.member, can_assign_as.tenant, k.key), false)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_user (
  member     uuid,
  scope      text,
  scope_id   uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when can_user.scope = 'platform' then better_supabase.platform_can(can_user.member, can_user.permission)
    when can_user.scope in ('organization', 'tenant') then better_supabase.member_can(can_user.member, can_user.scope_id, can_user.permission)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cap_allows (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when jwt is null then true
    when jsonb_typeof(cap) = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(cap) c(key)
        where better_supabase.permission_matches(c.key, cap_allows.permission)
      ) then false
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    else exists (
      select 1
      from unnest(case jsonb_typeof(jwt -> 'scope')
          when 'string' then regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+')
          when 'array' then array(select jsonb_array_elements_text(jwt -> 'scope'))
          else '{}'::text[]
        end) s(scope)
      cross join lateral unnest(better_supabase.scope_permissions(s.scope)) k(key)
      where s.scope <> ''
        and better_supabase.permission_matches(k.key, cap_allows.permission)
    )
  end
  from (select auth.jwt() as jwt) as token
  cross join lateral (
    select coalesce(jwt -> 'bsb_permission_cap', jwt -> 'bs_permission_cap') as cap
  ) as capped
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_attachment_upload (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.upload'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.column_default (
  relation text,
  name     text,
  target   anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  result alias for $0;
  v_default text;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = pg_catalog.to_regclass(column_default.relation) and a.attname = column_default.name and not a.attisdropped;
  if v_default is not null then
    execute 'select ' || v_default into result;
  end if;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.confirm_attachment (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."attachments";
  v_meta jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = confirm_attachment.id for update;
  if v_row."id" is null or (v_row."uploaded_by" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No pending attachment of yours has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
  if not found then
    raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
  end if;
  update "better_supabase"."attachments" a set
    "uploaded_at" = now(),
    "size" = coalesce((v_meta ->> 'size')::bigint, a."size"),
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type")
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_attachment (
  tenant        uuid,
  name          text,
  mime_type     text,
  size          bigint,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  metadata      jsonb   DEFAULT NULL::jsonb,
  width         integer DEFAULT NULL::integer,
  height        integer DEFAULT NULL::integer,
  pages         integer DEFAULT NULL::integer,
  document_type text    DEFAULT NULL::text,
  source        text    DEFAULT NULL::text,
  external_id   text    DEFAULT NULL::text,
  source_path   text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."attachments";
  v_columns text;
begin
  v_row := jsonb_populate_record(null::"better_supabase"."attachments", (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each('{}'::jsonb) as e (field_key, field_value)
    where e.field_key = any (array[]::text[])
  ));
  v_row."tenant_id" := create_attachment.tenant;
  v_row."bucket" := 'attachments';
  v_row."name" := create_attachment.name;
  v_row."mime_type" := lower(create_attachment.mime_type);
  v_row."size" := create_attachment.size;
  v_row."subject_type" := create_attachment.subject_type;
  v_row."subject_id" := create_attachment.subject_id;
  v_row."metadata" := coalesce(create_attachment.metadata, '{}');
  v_row."width" := create_attachment.width;
  v_row."height" := create_attachment.height;
  v_row."pages" := create_attachment.pages;

  if create_attachment.document_type is not null then
    select y."id" into v_row."document_type_id" from "better_supabase"."attachment_document_types" y
    where y."tenant_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"tenant_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
    || array(select quote_ident(k) from jsonb_object_keys('{}'::jsonb) as k
      where k = any (array[]::text[]))) as column_name;
  execute format('insert into "better_supabase"."attachments" as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_organization (
  attrs jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  case "better_supabase"."organization_slug_problem"(coalesce(attrs ->> 'slug', ''), null)
    when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  insert into "better_supabase"."organizations" ("name", "slug", "created_by")
  select r."name", r."slug", owner
  from jsonb_populate_record(null::"better_supabase"."organizations", attrs) r
  returning "id" into organization;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, 'owner');
  perform "better_supabase"."seed_tenant_defaults"(organization);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  null;
  return organization;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_team (
  tenant      uuid,
  name        text,
  description text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.current_tenant_id()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.define_attachment_document_type (
  tenant uuid,
  key    text,
  name   text,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "better_supabase"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "better_supabase"."attachment_document_types" as t ("tenant_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_attachment (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with removed as (
    delete from "better_supabase"."attachments" a where a."id" = delete_attachment.id returning 1
  )
  select exists (select 1 from removed)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_attachment_document_type (
  tenant uuid,
  key    text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."attachment_document_types" t
  where t."tenant_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_team (
  team uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = delete_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = delete_team.team;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_organization_owner()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- The row lock serializes concurrent demotions and leaves, so two
  -- transactions can't each remove a different last owner.
  perform 1 from "better_supabase"."organizations" o where o."id" = old."organization_id" for update;
  if found and not exists (
      select 1 from "better_supabase"."memberships" m where m."organization_id" = old."organization_id" and m."role" = 'owner' and m."disabled_at" is null
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_attachment (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select (to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) from "better_supabase"."attachments" a where a."id" = get_attachment.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_membership()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if not (current_user in ('anon', 'authenticated')) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new."role" is not distinct from old."role" and new."disabled_at" is not distinct from old."disabled_at" then
    return new;
  end if;
  perform "better_supabase"."guard_membership_role"(
    new."organization_id", new."user_id", new."role"::text,
    case when tg_op = 'UPDATE' then old."organization_id" end,
    case when tg_op = 'UPDATE' then old."role"::text end
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_membership_role (
  target_tenant   uuid,
  target_member   uuid,
  target_role     text,
  previous_tenant uuid,
  previous_role   text
)
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if target_member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(target_tenant, target_role::text)
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, previous_role::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.guard_profile()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.has_organization_role (
  organization uuid,
  roles        text[] DEFAULT NULL::text[]
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1
    from "better_supabase"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_run()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.is_platform (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(better_supabase.platform_can(auth.uid(), is_platform.permission), false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.leave_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_attachment_document_types (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."tenant_id" = list_attachment_document_types.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_attachment_versions (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(v) order by v."version" desc), '[]'::jsonb)
  from "better_supabase"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_attachments (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."tenant_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  ),
  m as (select "better_supabase"."attachment_authors"(array(select p."id" from page p)) as authors)
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) || jsonb_build_object('author', m.authors -> a."id"::text) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a, m;
  return v_files;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_members (
  organization uuid
)
  RETURNS TABLE (
    user_id     uuid,
    role        text,
    disabled_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m."user_id", m."role"::text, m."disabled_at"
  from "better_supabase"."memberships" m
  where m."organization_id" = organization
  order by m."user_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_organizations()
  RETURNS TABLE (
    id          uuid,
    name        text,
    slug        text,
    role        text,
    disabled_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select o."id", o."name", o."slug", m."role"::text, m."disabled_at"
  from "better_supabase"."memberships" m
  join "better_supabase"."organizations" o on o."id" = m."organization_id"
  where m."user_id" = (select auth.uid()) and o."deleted_at" is null and o."disabled_at" is null
    and not better_supabase.tenant_disabled(o."id")
  order by o."name"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_teams (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t."id",
    'name', t."name",
    'slug', t."slug",
    'description', t."description",
    'status', t."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb)
  ) order by t."name"), '[]'::jsonb)
  from "better_supabase"."teams" t
  where t."tenant_id" = list_teams.tenant
    and (
      auth.role() = 'service_role'
      or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_attachment_missing (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_used (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_can (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and not better_supabase.user_disabled(member)
    and not better_supabase.tenant_disabled(tenant)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(member_can.permission))
    and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_can_while_deleting (
  member     uuid,
  tenant     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and not better_supabase.user_disabled(member)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(member_can_while_deleting.permission))
    and exists (
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_organization_ids (
  roles text[] DEFAULT NULL::text[]
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  ROWS 1
  SET search_path TO ''
  AS $function$
  select m."organization_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_permissions (
  member uuid,
  tenant uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
$function$;

CREATE OR REPLACE FUNCTION better_supabase.membership_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_get (
  key text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select nullif(pg_catalog.current_setting('better_supabase.memo.' || key, true), '')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_set (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select pg_catalog.set_config('better_supabase.memo.' || key, value, true)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_subject_refs (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_fn regproc;
begin
  for v_fn in
    select p.oid::regproc
    from pg_catalog.pg_proc p
    join pg_catalog.pg_description d on d.objoid = p.oid and d.classoid = 'pg_catalog.pg_proc'::regclass and d.objsubid = 0
    where d.description = 'better-supabase:subject-merge'
      -- Only the owner's functions, so a marked function in a schema another
      -- role can write to never runs with this function's rights.
      and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
    order by p.oid::regproc::text
  loop
    execute format('select %s($1, $2, $3)', v_fn) using subject_table, keep, drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mirror_profile_email()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."profiles" set "email" = lower(new.email) where "id" = new.id and "email" is distinct from lower(new.email);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_permissions (
  tenant uuid,
  keys   text[] DEFAULT NULL::text[]
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when auth.uid() is null or my_permissions.tenant is null then '{}'::text[]
    when my_permissions.keys is not null then coalesce((
      select array_agg(distinct k order by k)
      from unnest(my_permissions.keys) as k
      where better_supabase.can('tenant', my_permissions.tenant, k)
    ), '{}'::text[])
    when better_supabase.tenant_disabled(my_permissions.tenant) then '{}'::text[]
    else coalesce((
      select array_agg(distinct p order by p)
      from unnest(better_supabase.member_permissions(auth.uid(), my_permissions.tenant)) as p
      where better_supabase.cap_allows(p)
    ), '{}'::text[])
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_profile()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.object_clean (
  bucket text,
  path   text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."scanned_objects" s
    where s."bucket" = object_clean.bucket and s."object_path" = object_clean.path and s."status" = 'clean'
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.object_scan (
  bucket text,
  path   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(s.*) from "better_supabase"."scanned_objects" s
  where s."bucket" = object_scan.bucket and s."object_path" = object_scan.path
$function$;

CREATE OR REPLACE FUNCTION better_supabase.on_auth_user_created()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_member_role (
  organization uuid,
  member       uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select m."role" from "better_supabase"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_member_roles (
  organization uuid,
  member       uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select array[m."role"]::text[]
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_overview (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from "better_supabase"."list_my_organizations"() o
  where o.id = organization_overview.organization;
  if v_org is null then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from "better_supabase"."list_members"(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', '[]'::jsonb
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_slug_problem (
  value               text,
  except_organization uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when value is null then null
    when length(value) < 2 or length(value) > 48 or value !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when false then 'reserved'
    when exists (
      select 1 from "better_supabase"."organizations" o
      where lower(o."slug"::text) = lower(value) and o."deleted_at" is null
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_claims (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when permission_claims.tenant is null then '{}'::jsonb
    else coalesce(jsonb_strip_nulls(jsonb_build_object(permission_claims.tenant::text, to_jsonb(better_supabase.member_permissions(permission_claims.user_id, permission_claims.tenant)))), '{}'::jsonb)
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_matches (
  granted text,
  wanted  text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select granted = '*' or granted = wanted
    or (right(granted, 2) = '.*' and starts_with(wanted, left(granted, -1)))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.platform_can (
  member     uuid,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select member is not null
    and (platform_can.member is distinct from auth.uid() or auth.jwt() -> 'act' is null)
    and not better_supabase.user_disabled(member)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(platform_can.permission))
    and ((platform_can.member = auth.uid() and exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')) = 'array'
        then coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')
        else '[]'::jsonb end
    ) g(key)
    where better_supabase.permission_matches(g.key, platform_can.permission)
  )))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.raise_actor_readonly()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_team_member (
  team   uuid,
  member uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
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
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("tenant_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at", "sha256", "hash_verified_at")
    values (v_row."tenant_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at", v_row."sha256", v_row."hash_verified_at");
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
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replace_equivalent_triggers (
  target          regclass,
  module_trigger  text,
  pattern         text,
  replace_trigger boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
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
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
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
    insert into "better_supabase"."attachment_versions" ("tenant_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at", "sha256", "hash_verified_at")
    values (v_row."tenant_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at", v_row."sha256", v_row."hash_verified_at");
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
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resume_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
  is_owner boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'You cannot resume yourself' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to resume members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  perform 1 from "better_supabase"."organizations" o where o."id" = organization for update;
  select m."role"::text, m."role" = 'owner' into current_role_value, is_owner
  from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "better_supabase"."memberships" set "disabled_at" = null
  where "organization_id" = organization and "user_id" = member and "disabled_at" is not null;
  if not found then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'resumed';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_grants (
  role       text,
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.export', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'agents.*', 'ai_files.*', 'ai_keys.*', 'ai_schedules.*', 'connectors.*', 'knowledge.*', 'memory.*', 'tags.*', 'teams.*', 'subjects.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'option_sets.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'legal_entities.*', 'document_templates.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*', 'qualifications.*', 'risks.*', 'advisories.*', 'shifts.*', 'consents.*', 'waitlist.invite', 'accounting.*', 'observations.*', 'medications.*', 'care_plans.*', 'cases.*', 'inspections.*', 'meetings.*', 'maintenance.*', 'dam.*', 'lims.*', 'appraisals.*', 'warehouse.*', 'rfqs.*', 'tills.*', 'periods.*', 'deadlines.*', 'commissions.*', 'referrals.*', 'agent_checkout.*', 'clinical_decision_support.*', 'e_prescribing.*', 'manufacturing.*', 'banking.*', 'tax.*', 'funding.*', 'payroll_export.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'agents.read', 'agents.write', 'agents.publish', 'ai_files.upload', 'ai_keys.use', 'ai_schedules.write', 'connectors.read', 'connectors.use', 'knowledge.read', 'knowledge.write', 'memory.read', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'option_sets.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'acknowledgements.acknowledge', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'shifts.read', 'shifts.request', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'legal_entities.read', 'document_templates.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read', 'risks.read', 'advisories.read', 'observations.read', 'observations.record', 'care_plans.read', 'cases.read', 'cases.create', 'manufacturing.read', 'manufacturing.produce', 'banking.read', 'banking.reconcile', 'tax.read', 'funding.read', 'funding.register']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.scope_permissions (
  scope text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select array[scope]
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_attachments_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'contract', 'Contract', '{"counterparty":{"type":"text","required":true},"signed_on":{"type":"date"},"expires_on":{"type":"expiry"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'contract');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'invoice', 'Invoice', '{"number":{"type":"text","required":true},"issued_on":{"type":"date"},"amount":{"type":"amount"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'invoice');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'receipt', 'Receipt', '{"merchant":{"type":"text"},"paid_on":{"type":"date"},"amount":{"type":"amount"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'receipt');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'identity', 'Identity document', '{"number":{"type":"text"},"expires_on":{"type":"expiry"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'identity');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'report', 'Report', '{}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'report');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'other', 'Other', '{}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'other');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_tenant_defaults (
  p_tenant   uuid,
  p_variants jsonb DEFAULT '{}'::jsonb,
  p_locale   text  DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform "better_supabase"."seed_attachments_defaults"(p_tenant, p_variants ->> 'attachments', p_locale);
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
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_object_scan (
  bucket text,
  path   text,
  status text,
  detail text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."scanned_objects";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_object_scan.status not in ('pending', 'clean', 'infected', 'failed') then
    raise exception 'status must be pending, clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  insert into "better_supabase"."scanned_objects" as s ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (set_object_scan.bucket, set_object_scan.path, set_object_scan.status, set_object_scan.detail,
    case when set_object_scan.status = 'pending' then null else now() end)
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at"
    where s."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."bucket" is null then
    select * into v_row from "better_supabase"."scanned_objects" s where s."bucket" = set_object_scan.bucket and s."object_path" = set_object_scan.path;
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  -- The default column is assigned directly; jsonb_populate_record copies the
  -- whole row, so it only serves other column names.
  if tg_nargs = 0 or tg_argv[0] = 'updated_at' then
    new.updated_at := now();
  else
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], now()));
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.suspend_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
  is_owner boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'You cannot suspend yourself' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to suspend members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  perform 1 from "better_supabase"."organizations" o where o."id" = organization for update;
  select m."role"::text, m."role" = 'owner' into current_role_value, is_owner
  from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  if is_owner and not exists (
    select 1 from "better_supabase"."memberships" o
    where o."organization_id" = organization and o."user_id" <> member and o."role" = 'owner' and o."disabled_at" is null
  ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  update "better_supabase"."memberships" set "disabled_at" = now()
  where "organization_id" = organization and "user_id" = member and "disabled_at" is null;
  if not found then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'suspended';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.switch_organization (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null or not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  -- The server's tenant resolver picks the tenant per request.
  update "better_supabase"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  null;
  return jsonb_build_object('organization_id', organization, 'refresh', false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_profile (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "better_supabase"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), lower(u.email), "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.team_ids_of (
  member uuid
)
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_disabled (
  tenant uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (select 1 from "better_supabase"."organizations" t where t."id" = tenant_disabled.tenant and (t."disabled_at" is not null or t."deleted_at" is not null))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_ids_with (
  permission text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  ROWS 1
  SET search_path TO ''
  AS $function$
  select m."organization_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_updated_at (
  target          regclass,
  column_name     text     DEFAULT 'updated_at'::text,
  replace_trigger boolean  DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_updated_at', 'updated_at|moddatetime|touch', replace_trigger
  );
  execute format('drop trigger if exists bsb_updated_at on %s', target);
  execute format(
    'create trigger bsb_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transfer_ownership (
  organization uuid,
  new_owner    uuid,
  former_role  text DEFAULT 'admin'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = me and m."role" = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner and m."disabled_at" is not null) then
    raise exception 'The new owner is suspended' using errcode = '42501', hint = 'ORGANIZATION_MEMBER_SUSPENDED';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners sees the transfer as a whole.
  update "better_supabase"."memberships" m set "role" = case
      when m."user_id" = new_owner then 'owner'
      else former_role
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and m."role" = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.try_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  result alias for $0;
begin
  result := value;
  return result;
exception when data_exception or check_violation then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_member_role (
  organization uuid,
  member       uuid,
  role         text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever blocks.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and coalesce(member = auth.uid(), false) then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "better_supabase"."memberships" set "role" = role
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_my_profile (
  attrs jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "locale" = case when update_my_profile.attrs ? 'locale' then update_my_profile.attrs ->> 'locale' else p."locale" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_organization (
  organization uuid,
  attrs        jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(coalesce(attrs ->> 'slug', ''), organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "better_supabase"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"better_supabase"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_team (
  team        uuid,
  name        text,
  description text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.user_disabled (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select false
$function$;

CREATE OR REPLACE FUNCTION better_supabase.value_unsupported (
  label text
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'the app does not support the value %', label
    using errcode = '22023', hint = 'VALUE_UNSUPPORTED';
end;
$function$;

CREATE OR REPLACE FUNCTION public.job_attachments_insert()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  insert into better_supabase.attachments (tenant_id, subject_type, subject_id, bucket, object_path, name, mime_type, size)
  values (new.organization_id, 'job', new.job_id::text, coalesce(new.bucket, 'attachments'), new.object_path, new.name, new.mime_type, new.size)
  returning id into new.id;
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."job_attachments_insert"() FROM "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.jobs_audit()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  ignored text[] := array['updated_at'];
  changed jsonb := '{}';
begin
  if tg_op = 'UPDATE' then
    select coalesce(jsonb_object_agg(n.key, n.value), '{}') into changed
    from jsonb_each(to_jsonb(new)) n
    where to_jsonb(old) -> n.key is distinct from n.value
      and n.key <> all (ignored);

    if changed = '{}' then
      return new;
    end if;
  end if;

  insert into public.job_audit (job_id, organization_id, action, changed)
  values (new.id, new.organization_id, lower(tg_op), changed);

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."jobs_audit"() FROM PUBLIC, "anon", "authenticated", "service_role";

CREATE OR REPLACE FUNCTION public.lienlink_on_user_created()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into public.user_signups (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."lienlink_on_user_created"() FROM PUBLIC, "anon", "authenticated", "service_role";

ALTER TABLE "better_supabase"."attachment_versions"
  ADD CONSTRAINT "attachment_versions_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "attachments_document_type_id_fkey" FOREIGN KEY (document_type_id) REFERENCES better_supabase.attachment_document_types(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."attachment_versions"
  ADD CONSTRAINT "attachment_versions_attachment_id_fkey" FOREIGN KEY (attachment_id) REFERENCES better_supabase.attachments(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "bsb_attachments_bucket" CHECK ((bucket = 'attachments'::text)) NOT VALID;

ALTER TABLE "better_supabase"."memberships"
  ADD CONSTRAINT "memberships_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."organizations"
  ADD CONSTRAINT "organizations_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."memberships"
  ADD CONSTRAINT "memberships_organization_fkey" FOREIGN KEY (organization_id) REFERENCES better_supabase.organizations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."profiles"
  ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_membership_fkey" FOREIGN KEY (tenant_id, user_id) REFERENCES better_supabase.memberships(organization_id, user_id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_team_id_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.teams(id) ON DELETE CASCADE;

ALTER TABLE "public"."jobs"
  ADD CONSTRAINT "jobs_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES better_supabase.organizations(id) ON DELETE CASCADE;

ALTER TABLE "public"."jobs"
  ADD CONSTRAINT "jobs_team_fkey" FOREIGN KEY (organization_id, team_id) REFERENCES better_supabase.teams(tenant_id, id);

ALTER TABLE "public"."user_signups"
  ADD CONSTRAINT "user_signups_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE VIEW "public"."memberships" WITH (security_invoker=true) AS  SELECT id,
    organization_id,
    user_id,
    role,
    created_at
   FROM better_supabase.memberships;

REVOKE ALL ON TABLE "public"."memberships" FROM "anon";

CREATE VIEW "public"."organizations" WITH (security_invoker=true) AS  SELECT id,
    name,
    slug,
    created_at,
    disabled_at,
    deleted_at
   FROM better_supabase.organizations;

REVOKE ALL ON TABLE "public"."organizations" FROM "anon";

CREATE VIEW "public"."profiles" WITH (security_invoker=true) AS  SELECT id,
    email,
    username,
    full_name,
    avatar_url,
    locale,
    active_organization_id,
    active_team_id,
    created_at,
    updated_at
   FROM better_supabase.profiles;

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";

CREATE VIEW "public"."team_members" WITH (security_invoker=true) AS  SELECT team_id,
    user_id,
    created_at
   FROM better_supabase.team_members;

REVOKE ALL ON TABLE "public"."team_members" FROM "anon";

CREATE VIEW "public"."teams" WITH (security_invoker=true) AS  SELECT id,
    tenant_id AS organization_id,
    name,
    slug,
    description,
    status,
    created_at,
    updated_at
   FROM better_supabase.teams;

REVOKE ALL ON TABLE "public"."teams" FROM "anon";

CREATE INDEX attachment_versions_uploaded_by_idx ON better_supabase.attachment_versions USING btree (uploaded_by);

CREATE INDEX attachments_document_type_idx ON better_supabase.attachments USING btree (document_type_id)
  WHERE (document_type_id IS NOT NULL);

CREATE UNIQUE INDEX attachments_external_idx ON better_supabase.attachments USING btree (tenant_id, source, external_id)
  WHERE (source IS NOT NULL);

CREATE INDEX attachments_job_id_idx ON better_supabase.attachments USING btree (job_id);

CREATE UNIQUE INDEX attachments_object_idx ON better_supabase.attachments USING btree (bucket, object_path);

CREATE INDEX attachments_subject_idx ON better_supabase.attachments USING btree (tenant_id, subject_type, subject_id);

CREATE INDEX memberships_user_idx ON better_supabase.memberships USING btree (user_id);

CREATE INDEX organizations_created_by_idx ON better_supabase.organizations USING btree (created_by);

CREATE UNIQUE INDEX organizations_slug_idx ON better_supabase.organizations USING btree (lower(slug))
  WHERE (deleted_at IS NULL);

CREATE UNIQUE INDEX profiles_username_idx ON better_supabase.profiles USING btree (lower(username));

CREATE INDEX team_members_membership_idx ON better_supabase.team_members USING btree (tenant_id, user_id);

CREATE INDEX team_members_user_idx ON better_supabase.team_members USING btree (user_id);

CREATE INDEX job_audit_job_id_idx ON public.job_audit USING btree (job_id);

CREATE INDEX job_audit_organization_id_idx ON public.job_audit USING btree (organization_id);

CREATE INDEX jobs_organization_id_idx ON public.jobs USING btree (organization_id);

CREATE INDEX jobs_team_id_idx ON public.jobs USING btree (organization_id, team_id);

CREATE TRIGGER bsb_profile_email
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.mirror_profile_email();

CREATE TRIGGER bsb_profile_sync
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.on_auth_user_created();

CREATE TRIGGER lienlink_on_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.lienlink_on_user_created();

CREATE TRIGGER bsb_attachments_changed
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.attachments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_changed();

CREATE TRIGGER bsb_attachments_documents
  BEFORE INSERT OR UPDATE ON better_supabase.attachments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachment_document_guard();

CREATE TRIGGER bsb_attachments_object_path
  BEFORE INSERT OR UPDATE ON better_supabase.attachments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachment_object_path();

CREATE CONSTRAINT TRIGGER bsb_organization_owner
  AFTER DELETE OR UPDATE OF ROLE, organization_id, disabled_at ON better_supabase.memberships DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.ensure_organization_owner();

CREATE TRIGGER bsb_organization_role_guard
  BEFORE INSERT OR UPDATE ON better_supabase.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_membership();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.organizations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_profile_guard
  BEFORE UPDATE ON better_supabase.profiles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.guard_profile();

CREATE TRIGGER jobs_audit
  AFTER INSERT OR UPDATE ON public.jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.jobs_audit();

CREATE POLICY "bsb_attachment_document_types_read" ON "better_supabase"."attachment_document_types"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."attachment_document_types"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachment_document_types"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachment_document_types"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."attachment_document_types"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_attachment_versions_read" ON "better_supabase"."attachment_versions"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.attachments a
  WHERE (a.id = attachment_versions.attachment_id))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."attachment_versions"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachment_versions"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachment_versions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.attachments a
  WHERE (a.id = attachment_versions.attachment_id)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."attachment_versions"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_attachments_read" ON "better_supabase"."attachments"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) AND better_supabase.attachment_subject_readable(subject_type,
    subject_id, tenant_id)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) AND better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_memberships_read" ON "better_supabase"."memberships"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."memberships"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."memberships"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."memberships"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.member_organization_ids() AS member_organization_ids)))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."memberships"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_organizations_read" ON "better_supabase"."organizations"
  FOR SELECT
  TO "authenticated"
  USING ((id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_profiles_read" ON "better_supabase"."profiles"
  FOR SELECT
  TO "authenticated"
  USING ((id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_profiles_update" ON "better_supabase"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING (((id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_team_members_read" ON "better_supabase"."team_members"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."team_members"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."team_members"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."team_members"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS
    tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."team_members"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_teams_read" ON "better_supabase"."teams"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."teams"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."teams"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."teams"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS
    tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."teams"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "job_audit_member_select" ON "public"."job_audit"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "job_audit_no_delete" ON "public"."job_audit"
  AS RESTRICTIVE
  FOR DELETE
  TO "authenticated"
  USING (false);

CREATE POLICY "job_audit_no_insert" ON "public"."job_audit"
  AS RESTRICTIVE
  FOR INSERT
  TO "authenticated"
  WITH CHECK (false);

CREATE POLICY "job_audit_no_update" ON "public"."job_audit"
  AS RESTRICTIVE
  FOR UPDATE
  TO "authenticated"
  USING (false);

CREATE POLICY "jobs_member_insert" ON "public"."jobs"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "jobs_member_select" ON "public"."jobs"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "jobs_member_update" ON "public"."jobs"
  FOR UPDATE
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "jobs_no_delete" ON "public"."jobs"
  AS RESTRICTIVE
  FOR DELETE
  TO "authenticated"
  USING (false);

CREATE POLICY "user_signups_own_select" ON "public"."user_signups"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bsb_attachments_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'attachments:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 13) IN ( SELECT
    (x.x)::text AS x
   FROM better_supabase.tenant_ids_with('attachments.read'::text) x(x)))));

CREATE POLICY "bsb_attachments_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'delete'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_attachments_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'insert'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bsb_attachments_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'attachments'::text) AND better_supabase.attachment_object_allowed(bucket_id, name, 'select'::text)));

COMMENT ON COLUMN "better_supabase"."attachments"."object_path" IS 'better-supabase path: {organization_id}/attachments/{id}';

REVOKE ALL ON FUNCTION "better_supabase"."acting_member"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."acting_member"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."actor_may_write"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."actor_may_write"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_team_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_team_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."allocate_username"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."allocate_username"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_team"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."as_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."as_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachment_authors"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_authors"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachment_document_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."attachment_fields_error"(jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_fields_error"(jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachment_object_allowed"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_object_allowed"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachment_object_path"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."attachment_object_visible"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_object_visible"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachment_schema_error"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_schema_error"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachment_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attachment_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attachments_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."backfill_profiles"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."backfill_profiles"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can"(text, uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_assign"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign"(uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign_as"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."can_user"(uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_user"(uuid, text, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."cap_allows"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cap_allows"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_attachment_upload"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_attachment_upload"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."column_default"(text, text, anyelement) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."confirm_attachment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."confirm_attachment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_organization"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_organization"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_team"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_team"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."current_tenant_id"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."current_tenant_id"() TO "anon", "authenticated", "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_attachment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_attachment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_attachment_document_type"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_attachment_document_type"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_team"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ensure_organization_owner"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."get_attachment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_attachment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."guard_membership"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."guard_profile"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_run"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_run"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."is_platform"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."is_platform"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."leave_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."leave_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_attachment_document_types"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_attachment_document_types"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_attachment_versions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_attachment_versions"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_attachments"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_attachments"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_members"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_members"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_my_organizations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_my_organizations"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_teams"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_teams"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_attachment_missing"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_attachment_missing"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_used"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_used"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_can_while_deleting"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_can_while_deleting"(uuid, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."member_organization_ids"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_organization_ids"(text[]) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."member_permissions"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_permissions"(uuid, uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."membership_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."membership_claims"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."merge_subject_refs"(text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."mirror_profile_email"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."my_permissions"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_permissions"(uuid, text[]) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_profile"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_profile"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."object_clean"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."object_clean"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."object_scan"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."object_scan"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."on_auth_user_created"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."operation_permission"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."operation_permission"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_member_role"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_member_role"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_member_roles"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_member_roles"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_overview"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_overview"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_slug_problem"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_slug_problem"(text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims"(uuid, uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."permission_matches"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_matches"(text, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."platform_can"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."platform_can"(uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."raise_actor_readonly"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."raise_actor_readonly"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_team_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_team_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replace_equivalent_triggers"(regclass, text, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."restore_attachment_version"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_attachment_version"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resume_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resume_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."role_grants"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."role_grants"(text, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."role_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."role_permissions"(text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."scope_permissions"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."scope_permissions"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_attachments_defaults"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_attachments_defaults"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."seed_tenant_defaults"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."seed_tenant_defaults"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_attachment_status"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_attachment_status"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_object_scan"(text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_object_scan"(text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."suspend_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."suspend_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."switch_organization"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."switch_organization"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sync_profile"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sync_profile"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."team_ids_of"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."team_ids_of"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_disabled"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_ids_with"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_ids_with"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."track_updated_at"(regclass, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."transfer_ownership"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."transfer_ownership"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."try_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."try_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_member_role"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_member_role"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_my_profile"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_my_profile"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_organization"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_organization"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_team"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_team"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."user_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."user_disabled"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."value_unsupported"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."value_unsupported"(text) TO "anon", "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."job_attachments_insert"() TO PUBLIC;

REVOKE ALL ON FUNCTION "public"."job_attachments_insert"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."job_attachments_insert"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."jobs_audit"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."jobs_audit"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."lienlink_on_user_created"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."lienlink_on_user_created"() TO "postgres";

GRANT USAGE ON SCHEMA "better_supabase" TO "anon", "authenticated", "service_role", "supabase_auth_admin";

GRANT SELECT ON TABLE "better_supabase"."attachment_document_types" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."attachment_document_types" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."attachment_versions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."attachment_versions" TO "service_role";

GRANT INSERT ("bucket") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("document_type_id") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("external_id") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("height") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("metadata") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("mime_type") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("name") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("pages") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("size") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("source_path") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("source") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("subject_id") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("subject_type") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("tenant_id") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT INSERT ("width") ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT DELETE, SELECT ON TABLE "better_supabase"."attachments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."attachments" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."blocks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."memberships" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."memberships" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."organizations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."organizations" TO "service_role";

GRANT UPDATE ("avatar_path") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("avatar_url") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("first_name") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("full_name") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("last_name") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("locale") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("onboarding") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("updated_at") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT UPDATE ("username") ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT SELECT ON TABLE "better_supabase"."profiles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."profiles" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."scanned_objects" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."team_members" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."team_members" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."teams" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."teams" TO "service_role";

REVOKE ALL ON TABLE "public"."job_audit" FROM "authenticated";

GRANT SELECT ON TABLE "public"."job_audit" TO "authenticated";

REVOKE ALL ON TABLE "public"."job_audit" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."job_audit" TO "postgres";

REVOKE ALL ON TABLE "public"."job_audit" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."job_audit" TO "service_role";

REVOKE ALL ON TABLE "public"."jobs" FROM "authenticated";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."jobs" TO "authenticated";

REVOKE ALL ON TABLE "public"."jobs" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."jobs" TO "postgres";

REVOKE ALL ON TABLE "public"."jobs" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."jobs" TO "service_role";

REVOKE ALL ON TABLE "public"."user_signups" FROM "authenticated";

GRANT SELECT ON TABLE "public"."user_signups" TO "authenticated";

REVOKE ALL ON TABLE "public"."user_signups" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."user_signups" TO "postgres";

REVOKE ALL ON TABLE "public"."user_signups" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."user_signups" TO "service_role";

REVOKE ALL ON TABLE "public"."memberships" FROM "authenticated";

GRANT SELECT ON TABLE "public"."memberships" TO "authenticated";

REVOKE ALL ON TABLE "public"."memberships" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."memberships" TO "postgres";

REVOKE ALL ON TABLE "public"."memberships" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."memberships" TO "service_role";

REVOKE ALL ON TABLE "public"."organizations" FROM "authenticated";

GRANT SELECT ON TABLE "public"."organizations" TO "authenticated";

REVOKE ALL ON TABLE "public"."organizations" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."organizations" TO "postgres";

REVOKE ALL ON TABLE "public"."organizations" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."organizations" TO "service_role";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."profiles" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres";

REVOKE ALL ON TABLE "public"."profiles" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."profiles" TO "service_role";

REVOKE ALL ON TABLE "public"."team_members" FROM "authenticated";

GRANT SELECT ON TABLE "public"."team_members" TO "authenticated";

REVOKE ALL ON TABLE "public"."team_members" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."team_members" TO "postgres";

REVOKE ALL ON TABLE "public"."team_members" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."team_members" TO "service_role";

REVOKE ALL ON TABLE "public"."teams" FROM "authenticated";

GRANT SELECT ON TABLE "public"."teams" TO "authenticated";

REVOKE ALL ON TABLE "public"."teams" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."teams" TO "postgres";

REVOKE ALL ON TABLE "public"."teams" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."teams" TO "service_role";

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "attachments_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE VIEW "public"."job_attachments" WITH (security_invoker=true) AS  SELECT id,
    tenant_id AS organization_id,
    job_id,
    bucket,
    object_path,
    name,
    mime_type,
    size,
    status,
    uploaded_by,
    created_at
   FROM better_supabase.attachments
  WHERE (subject_type = 'job'::text);

REVOKE ALL ON TABLE "public"."job_attachments" FROM "anon";

CREATE INDEX attachments_uploaded_by_idx ON better_supabase.attachments USING btree (uploaded_by);

CREATE TRIGGER job_attachments_insert
  INSTEAD OF INSERT ON public.job_attachments
  FOR EACH ROW
  EXECUTE FUNCTION public.job_attachments_insert();

CREATE POLICY "bsb_attachments_delete" ON "better_supabase"."attachments"
  FOR DELETE
  TO "authenticated"
  USING
    ((((uploaded_by = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('attachments.manage'::text) AS tenant_ids_with))) AND ( SELECT
    better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_attachments_insert" ON "better_supabase"."attachments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((uploaded_by = ( SELECT auth.uid() AS uid)) AND COALESCE(better_supabase.can('tenant'::text, tenant_id, 'attachments.upload'::text), false) AND
    better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.manage'::text) AS tenant_ids_with)))));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) AND
    COALESCE(better_supabase.can('tenant'::text, tenant_id, 'attachments.upload'::text), false) AND
    better_supabase.attachment_subject_readable(subject_type, subject_id, tenant_id))));

REVOKE ALL ON TABLE "public"."job_attachments" FROM "authenticated";

GRANT INSERT, SELECT ON TABLE "public"."job_attachments" TO "authenticated";

REVOKE ALL ON TABLE "public"."job_attachments" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."job_attachments" TO "postgres";

REVOKE ALL ON TABLE "public"."job_attachments" FROM "service_role";

GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE ON TABLE "public"."job_attachments" TO "service_role";
