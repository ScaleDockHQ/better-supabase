SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_trusted (
  event_type      text,
  category        text  DEFAULT NULL::text,
  outcome         text  DEFAULT 'success'::text,
  source          text  DEFAULT NULL::text,
  target_type     text  DEFAULT NULL::text,
  record_id       text  DEFAULT NULL::text,
  tenant          uuid  DEFAULT NULL::uuid,
  metadata        jsonb DEFAULT '{}'::jsonb,
  idempotency_key text  DEFAULT NULL::text,
  restricted      jsonb DEFAULT NULL::jsonb,
  actor_id        uuid  DEFAULT NULL::uuid,
  summary         text  DEFAULT NULL::text,
  target_label    text  DEFAULT NULL::text,
  correlation_id  text  DEFAULT NULL::text,
  actor_kind      text  DEFAULT NULL::text,
  actor_label     text  DEFAULT NULL::text,
  ip              inet  DEFAULT NULL::inet,
  user_agent      text  DEFAULT NULL::text,
  session_id      text  DEFAULT NULL::text,
  request_id      text  DEFAULT NULL::text,
  scope           text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set sql.modules.audit.options.restricted to true.';
  end if;
  actor_id := coalesce(actor_id, auth.uid());
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event_trusted.idempotency_key
      and l."organization_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end,
    auth.jwt() -> 'act' ->> 'reason',
    case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end,
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    null,
    target_label,
    summary,
    coalesce(request_id, better_supabase.request_header('x-request-id')),
    coalesce(correlation_id, better_supabase.request_header('x-correlation-id')),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

REVOKE ALL
  ON FUNCTION
    "better_supabase"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION
    "better_supabase"."audit_event_trusted"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  TO "service_role";
