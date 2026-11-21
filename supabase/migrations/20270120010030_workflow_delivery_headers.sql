SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.dispatch_workflow_deliveries (
  batch integer DEFAULT 20
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_url text;
  v_secret text;
  v_extra jsonb;
  v_job record;
  v_body jsonb;
  v_t text;
  v_job_header text;
  v_count integer := 0;
  -- pg_net is optional: http_post is looked up, not named, so plpgsql_check
  -- (supabase db lint) passes without the extension.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
begin
  if v_post is null then
    raise exception 'dispatch_workflow_deliveries needs pg_net: create extension pg_net, or deliver with the poll mode';
  end if;
  select ds.decrypted_secret into v_url from vault.decrypted_secrets ds where ds.name = 'workflow_flow_url';
  select ds.decrypted_secret into v_secret from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_secret';
  if v_url is null or v_secret is null then
    raise exception 'Set the Vault secrets workflow_flow_url and workflow_delivery_secret before dispatching' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  -- Extra headers (a deployment protection bypass, for one) as a JSON object.
  select ds.decrypted_secret::jsonb into v_extra from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_headers';
  if v_extra is not null and pg_catalog.jsonb_typeof(v_extra) <> 'object' then
    raise exception 'The Vault secret workflow_delivery_headers must be a JSON object of header names and values' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, coalesce(v_extra, '{}'::jsonb) || jsonb_build_object(
        'content-type', 'application/json',
        'x-bsb-job', v_job_header,
        'x-bsb-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), 30000;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;
