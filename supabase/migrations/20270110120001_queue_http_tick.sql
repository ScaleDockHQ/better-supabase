SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.http_tick()
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  -- pg_net and Vault are looked up, not named, so plpgsql_check (supabase db
  -- lint) passes without them.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
  v_url text;
  v_token text;
  v_id bigint;
begin
  if v_post is null then
    raise exception 'the queue tick needs pg_net: create extension pg_net'
      using hint = 'QUEUE_TICK_NO_PG_NET';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'the queue tick reads its URL and token from Vault: create extension supabase_vault'
      using hint = 'QUEUE_TICK_NO_VAULT';
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'jobs_tick_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_token using 'jobs_tick_token';
  if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
    raise warning 'http_tick skipped: set the Vault secrets jobs_tick_url and jobs_tick_token';
    return null;
  end if;
  execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
    into v_id
    using v_url, '{}'::jsonb, jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_token
    ), 55000;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unschedule_job (
  job_name text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_unschedule regprocedure := pg_catalog.to_regprocedure('cron.unschedule(text)');
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean;
  v_removed boolean;
begin
  if v_unschedule is null or v_jobs is null then
    return false;
  end if;
  -- cron.unschedule raises for a name it doesn't know.
  execute format('select exists (select 1 from %s j where j.jobname = $1)', v_jobs)
    into v_found
    using job_name;
  if not v_found then
    return false;
  end if;
  execute format('select %s($1::text)', v_unschedule::oid::regproc)
    into v_removed
    using job_name;
  return v_removed;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."http_tick"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."http_tick"() TO "service_role";
