SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.enqueue_import_chunks (
  run    uuid,
  entity text,
  chunks integer
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
  end loop;
  return enqueue_import_chunks.chunks;
end;
$function$;
