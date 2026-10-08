SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."ai_files"
  DROP CONSTRAINT "ai_files_filename_check";

CREATE TABLE "better_supabase"."memory_documents" (
  "scope_key"  text                     NOT NULL,
  "path"       text                     NOT NULL,
  "content"    text                     NOT NULL,
  "version"    bigint                   NOT NULL DEFAULT 1,
  "expires_at" timestamp with time zone,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "memory_documents_content_check" CHECK ((length(content) <= 100000)),
  CONSTRAINT "memory_documents_path_check" CHECK ((length(path) <= 1024)),
  CONSTRAINT "memory_documents_pkey" PRIMARY KEY (scope_key, path),
  CONSTRAINT "memory_documents_scope_key_check" CHECK ((length(scope_key) <= 4096))
);

ALTER TABLE "better_supabase"."memory_documents"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.memory_document_read (
  scope_key text,
  path      text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_document_read"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.memory_document_write (
  scope_key        text,
  path             text,
  content          text,
  expected_version text    DEFAULT NULL::text,
  expires_in       integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."memory_document_write"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.purge_memory_documents (
  batch integer DEFAULT 1000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_memory_documents"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_document_read (
  scope_key text,
  path      text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('content', x."content", 'version', x."version"::text)
  from "better_supabase"."memory_documents" x
  where x."scope_key" = memory_document_read.scope_key and x."path" = memory_document_read.path
    and (x."expires_at" is null or x."expires_at" > now())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_document_write (
  scope_key        text,
  path             text,
  content          text,
  expected_version text    DEFAULT NULL::text,
  expires_in       integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."memory_documents"%rowtype;
  v_expires timestamptz := case when memory_document_write.expires_in is null then null else now() + make_interval(secs => memory_document_write.expires_in) end;
begin
  if length(memory_document_write.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  delete from "better_supabase"."memory_documents" x
  where x."scope_key" = memory_document_write.scope_key and x."path" = memory_document_write.path
    and x."expires_at" <= now();
  if memory_document_write.expected_version is null then
    insert into "better_supabase"."memory_documents" ("scope_key", "path", "content", "expires_at")
    values (memory_document_write.scope_key, memory_document_write.path, memory_document_write.content, v_expires)
    on conflict ("scope_key", "path") do nothing
    returning * into v_row;
  else
    update "better_supabase"."memory_documents" x set "content" = memory_document_write.content, "version" = x."version" + 1,
      "expires_at" = v_expires, "updated_at" = now()
    where x."scope_key" = memory_document_write.scope_key and x."path" = memory_document_write.path
      and x."version"::text = memory_document_write.expected_version
    returning * into v_row;
  end if;
  if not found then
    raise exception '% changed since version %', memory_document_write.path, coalesce(memory_document_write.expected_version, 'none') using errcode = '40001', hint = 'MEMORY_DOCUMENT_CONFLICT';
  end if;
  return jsonb_build_object('content', v_row."content", 'version', v_row."version"::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_memory_documents (
  batch integer DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."memory_documents" x
  where (x."scope_key", x."path") in (
    select y."scope_key", y."path" from "better_supabase"."memory_documents" y
    where y."expires_at" <= now()
    limit least(greatest(purge_memory_documents.batch, 1), 10000)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

ALTER TABLE "better_supabase"."ai_files"
  ADD CONSTRAINT "ai_files_filename_check"
    CHECK ((((length(filename) >= 1) AND (length(filename) <= 255)) AND (filename !~ '[/\\]'::text) AND (filename <> ALL (ARRAY['.'::text, '..'::text]))));

CREATE INDEX memory_documents_expires_idx ON better_supabase.memory_documents USING btree (expires_at)
  WHERE (expires_at IS NOT NULL);

REVOKE ALL ON FUNCTION "api"."memory_document_read"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_document_read"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."memory_document_write"(text, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."memory_document_write"(text, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_memory_documents"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_memory_documents"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_document_read"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_document_read"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."memory_document_write"(text, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."memory_document_write"(text, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_memory_documents"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_memory_documents"(integer) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."memory_documents" TO "service_role";
