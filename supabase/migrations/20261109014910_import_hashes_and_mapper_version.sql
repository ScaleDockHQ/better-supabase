SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."import_runs"
  ADD COLUMN "mapper_version" text;

CREATE OR REPLACE FUNCTION api.export_import_hashes (
  tenant uuid,
  source text,
  entity text DEFAULT NULL::text
)
  RETURNS SETOF jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."export_import_hashes"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.reapply_import_records (
  tenant         uuid,
  source         text,
  mapper_version text,
  entity         text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reapply_import_records"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.export_import_hashes (
  tenant uuid,
  source text,
  entity text DEFAULT NULL::text
)
  RETURNS SETOF jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('entity', x."entity", 'scope', x."scope", 'key', x."external_key", 'role', x."role",
    'hash', x."content_hash", 'subjectType', x."subject_type", 'subjectId', x."subject_id")
  from "better_supabase"."import_records" x
  where x."tenant_id" = export_import_hashes.tenant and x."source" = export_import_hashes.source
    and (export_import_hashes.entity is null or x."entity" = export_import_hashes.entity)
  order by x."entity", x."scope", x."external_key", x."role"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_import_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = get_import_run.id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to read this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_run."id", 'organizationId', v_run."tenant_id", 'source', v_run."source", 'status', v_run."status", 'mapping', v_run."mapping", 'counts', v_run."counts", 'errors', v_run."errors", 'dryRun', v_run."dry_run", 'full', v_run."full", 'inputChecksum', v_run."input_checksum", 'correlationId', v_run."correlation_id", 'mapperVersion', v_run."mapper_version", 'scopeAliases', v_run."scope_aliases", 'createdBy', v_run."created_by", 'createdAt', v_run."created_at", 'startedAt', v_run."started_at", 'finishedAt', v_run."finished_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_runs (
  tenant    uuid,
  source    text    DEFAULT NULL::text,
  status    text    DEFAULT NULL::text,
  row_limit integer DEFAULT 50
)
  RETURNS SETOF jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_import_runs.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list imports' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  return query
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'source', r."source", 'status', r."status", 'mapping', r."mapping", 'counts', r."counts", 'errors', r."errors", 'dryRun', r."dry_run", 'full', r."full", 'inputChecksum', r."input_checksum", 'correlationId', r."correlation_id", 'mapperVersion', r."mapper_version", 'scopeAliases', r."scope_aliases", 'createdBy', r."created_by", 'createdAt', r."created_at", 'startedAt', r."started_at", 'finishedAt', r."finished_at")
    from "better_supabase"."import_runs" r
    where r."tenant_id" = list_import_runs.tenant
      and (list_import_runs.source is null or r."source" = list_import_runs.source)
      and (list_import_runs.status is null or r."status" = list_import_runs.status)
    order by r."created_at" desc, r."id" desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reapply_import_records (
  tenant         uuid,
  source         text,
  mapper_version text,
  entity         text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer;
begin
  update "better_supabase"."import_records" x set "content_hash" = ''
  where x."tenant_id" = reapply_import_records.tenant and x."source" = reapply_import_records.source
    and (reapply_import_records.entity is null or x."entity" = reapply_import_records.entity)
    and x."content_hash" <> ''
    and (select r."mapper_version" from "better_supabase"."import_runs" r where r."id" = x."last_run_id") is distinct from reapply_import_records.mapper_version;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_import_run (
  tenant  uuid,
  source  text,
  options jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', start_import_run.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    raise exception 'an import run needs a source' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    raise exception 'scopeAliases must be an array of { scope, of, entities }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    insert into "better_supabase"."import_runs" as r ("tenant_id", "source", "mapping", "dry_run", "full", "input_checksum", "correlation_id", "mapper_version", "scope_aliases", "created_by")
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      auth.uid()
    )
    returning r."id" into v_id;
  exception when unique_violation then
    raise exception 'an import of this source is already pending or running' using errcode = '55P03', hint = 'IMPORT_RUN_ACTIVE';
  end;
  return jsonb_build_object('id', v_id);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."export_import_hashes"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."export_import_hashes"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."reapply_import_records"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reapply_import_records"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."export_import_hashes"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."export_import_hashes"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reapply_import_records"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reapply_import_records"(uuid, text, text, text) TO "service_role";
