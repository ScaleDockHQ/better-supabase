SET local check_function_bodies = off;

DROP FUNCTION "api"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid);

CREATE OR REPLACE FUNCTION api.create_webhook_endpoint (
  tenant uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_webhook_endpoint"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_webhook_endpoint (
  endpoint uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_webhook_endpoint"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_comments (
  tenant          uuid,
  subject_type    text,
  subject_id      text,
  after           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows        integer                  DEFAULT 100,
  skip            integer                  DEFAULT 0,
  after_id        uuid                     DEFAULT NULL::uuid,
  include_deleted boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_comments"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.list_webhook_endpoints (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_webhook_endpoints"($1) $function$;

CREATE OR REPLACE FUNCTION api.update_webhook_endpoint (
  endpoint uuid,
  fields   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_webhook_endpoint"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_webhook_endpoint (
  tenant uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := create_webhook_endpoint.tenant;
  v_id uuid;
  v_endpoint jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(create_webhook_endpoint.fields, '{}')) <> 'object' or exists (
    select 1 from jsonb_each(coalesce(create_webhook_endpoint.fields, '{}')) e
    where case e.key when 'name' then jsonb_typeof(e.value) <> 'string' when 'url' then jsonb_typeof(e.value) <> 'string' when 'enabled' then jsonb_typeof(e.value) <> 'boolean' when 'eventTypes' then (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string')) when 'permissions' then (jsonb_typeof(e.value) <> 'null' and (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string'))) when 'batch' then jsonb_typeof(e.value) <> 'boolean' when 'signing' then jsonb_typeof(e.value) <> 'string' when 'format' then jsonb_typeof(e.value) <> 'string' when 'credentialRef' then jsonb_typeof(e.value) not in ('object', 'null') else true end
  ) then
    raise exception 'A webhook endpoint field is unknown or has the wrong type' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_INVALID';
  end if;
  if create_webhook_endpoint.fields ->> 'url' is null or create_webhook_endpoint.fields ->> 'url' !~* '^https://' then
    raise exception 'A webhook endpoint URL must start with https://' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_URL';
  end if;
  insert into "better_supabase"."webhook_endpoints" ("organization_id", "url", "enabled", "event_types", "name")
  values (create_webhook_endpoint.tenant, create_webhook_endpoint.fields ->> 'url', coalesce((create_webhook_endpoint.fields ->> 'enabled')::boolean, true), coalesce(array(select jsonb_array_elements_text(create_webhook_endpoint.fields -> 'eventTypes')), '{}'), create_webhook_endpoint.fields ->> 'name')
  returning "id" into v_id;
  if create_webhook_endpoint.fields ?| array['permissions', 'batch', 'signing', 'format', 'credentialRef'] then
    update "better_supabase"."webhook_endpoints" d set "permissions" = case when create_webhook_endpoint.fields ? 'permissions' then case when jsonb_typeof(create_webhook_endpoint.fields -> 'permissions') = 'null' then null else array(select jsonb_array_elements_text(create_webhook_endpoint.fields -> 'permissions')) end else d."permissions" end, "batch" = case when create_webhook_endpoint.fields ? 'batch' then (create_webhook_endpoint.fields ->> 'batch')::boolean else d."batch" end, "signing" = case when create_webhook_endpoint.fields ? 'signing' then create_webhook_endpoint.fields ->> 'signing' else d."signing" end, "format" = case when create_webhook_endpoint.fields ? 'format' then create_webhook_endpoint.fields ->> 'format' else d."format" end, "credential_ref" = case when create_webhook_endpoint.fields ? 'credentialRef' then nullif(create_webhook_endpoint.fields -> 'credentialRef', 'null'::jsonb) else d."credential_ref" end, "updated_at" = now()
  where d."id" = v_id;
  end if;
  select jsonb_build_object('id', d."id", 'tenant', d."organization_id", 'name', d."name", 'url', d."url", 'enabled', d."enabled", 'eventTypes', d."event_types", 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credentialRef', d."credential_ref", 'failingSince', d."failing_since", 'disabledAt', d."disabled_at", 'disabledReason', d."disabled_reason", 'createdBy', d."created_by", 'createdAt', d."created_at", 'updatedAt', d."updated_at") into v_endpoint
  from "better_supabase"."webhook_endpoints" d where d."id" = v_id;
  return v_endpoint;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_webhook_endpoint (
  endpoint uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."organization_id" into v_tenant
  from "better_supabase"."webhook_endpoints" d where d."id" = delete_webhook_endpoint.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  delete from "better_supabase"."webhook_endpoints" d
  where d."id" = delete_webhook_endpoint.endpoint;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant          uuid,
  subject_type    text,
  subject_id      text,
  after           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows        integer                  DEFAULT 100,
  skip            integer                  DEFAULT 0,
  after_id        uuid                     DEFAULT NULL::uuid,
  include_deleted boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  perform "better_supabase"."record_subject_read"(list_comments.subject_type, list_comments.subject_id, null, 'comments', 'list_comments');
  return "better_supabase"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments.include_deleted, true) or x."deleted_at" is null)
      and (list_comments.after is null
        or (x."sent_at", x."id") > (list_comments.after, coalesce(list_comments.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_webhook_endpoints (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := list_webhook_endpoints.tenant;
  v_endpoints jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.read'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', d."id", 'tenant', d."organization_id", 'name', d."name", 'url', d."url", 'enabled', d."enabled", 'eventTypes', d."event_types", 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credentialRef', d."credential_ref", 'failingSince', d."failing_since", 'disabledAt', d."disabled_at", 'disabledReason', d."disabled_reason", 'createdBy', d."created_by", 'createdAt', d."created_at", 'updatedAt', d."updated_at") order by d."created_at" desc, d."id"), '[]')
  into v_endpoints
  from "better_supabase"."webhook_endpoints" d
  where d."organization_id" = list_webhook_endpoints.tenant;
  return v_endpoints;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_webhook_endpoint (
  endpoint uuid,
  fields   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_endpoint jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."organization_id" into v_tenant
  from "better_supabase"."webhook_endpoints" d where d."id" = update_webhook_endpoint.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(update_webhook_endpoint.fields, '{}')) <> 'object' or exists (
    select 1 from jsonb_each(coalesce(update_webhook_endpoint.fields, '{}')) e
    where case e.key when 'name' then jsonb_typeof(e.value) <> 'string' when 'url' then jsonb_typeof(e.value) <> 'string' when 'enabled' then jsonb_typeof(e.value) <> 'boolean' when 'eventTypes' then (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string')) when 'permissions' then (jsonb_typeof(e.value) <> 'null' and (jsonb_typeof(e.value) <> 'array' or exists (select 1 from jsonb_array_elements(e.value) a where jsonb_typeof(a) <> 'string'))) when 'batch' then jsonb_typeof(e.value) <> 'boolean' when 'signing' then jsonb_typeof(e.value) <> 'string' when 'format' then jsonb_typeof(e.value) <> 'string' when 'credentialRef' then jsonb_typeof(e.value) not in ('object', 'null') else true end
  ) then
    raise exception 'A webhook endpoint field is unknown or has the wrong type' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_INVALID';
  end if;
  if update_webhook_endpoint.fields ? 'url' then
    if update_webhook_endpoint.fields ->> 'url' is null or update_webhook_endpoint.fields ->> 'url' !~* '^https://' then
    raise exception 'A webhook endpoint URL must start with https://' using errcode = '22023', hint = 'WEBHOOK_ENDPOINT_URL';
  end if;
  end if;
  update "better_supabase"."webhook_endpoints" d set "name" = case when update_webhook_endpoint.fields ? 'name' then update_webhook_endpoint.fields ->> 'name' else d."name" end, "url" = case when update_webhook_endpoint.fields ? 'url' then update_webhook_endpoint.fields ->> 'url' else d."url" end, "enabled" = case when update_webhook_endpoint.fields ? 'enabled' then (update_webhook_endpoint.fields ->> 'enabled')::boolean else d."enabled" end, "event_types" = case when update_webhook_endpoint.fields ? 'eventTypes' then array(select jsonb_array_elements_text(update_webhook_endpoint.fields -> 'eventTypes')) else d."event_types" end, "permissions" = case when update_webhook_endpoint.fields ? 'permissions' then case when jsonb_typeof(update_webhook_endpoint.fields -> 'permissions') = 'null' then null else array(select jsonb_array_elements_text(update_webhook_endpoint.fields -> 'permissions')) end else d."permissions" end, "batch" = case when update_webhook_endpoint.fields ? 'batch' then (update_webhook_endpoint.fields ->> 'batch')::boolean else d."batch" end, "signing" = case when update_webhook_endpoint.fields ? 'signing' then update_webhook_endpoint.fields ->> 'signing' else d."signing" end, "format" = case when update_webhook_endpoint.fields ? 'format' then update_webhook_endpoint.fields ->> 'format' else d."format" end, "credential_ref" = case when update_webhook_endpoint.fields ? 'credentialRef' then nullif(update_webhook_endpoint.fields -> 'credentialRef', 'null'::jsonb) else d."credential_ref" end, "updated_at" = now()
  where d."id" = update_webhook_endpoint.endpoint;
  select jsonb_build_object('id', d."id", 'tenant', d."organization_id", 'name', d."name", 'url', d."url", 'enabled', d."enabled", 'eventTypes', d."event_types", 'permissions', d."permissions", 'batch', d."batch", 'signing', d."signing", 'format', d."format", 'credentialRef', d."credential_ref", 'failingSince', d."failing_since", 'disabledAt', d."disabled_at", 'disabledReason', d."disabled_reason", 'createdBy', d."created_by", 'createdAt', d."created_at", 'updatedAt', d."updated_at") into v_endpoint
  from "better_supabase"."webhook_endpoints" d where d."id" = update_webhook_endpoint.endpoint;
  return v_endpoint;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."create_webhook_endpoint"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_webhook_endpoint"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_webhook_endpoint"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_webhook_endpoint"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_webhook_endpoints"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_webhook_endpoints"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_webhook_endpoint"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_webhook_endpoint"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_webhook_endpoint"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_webhook_endpoint"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_webhook_endpoint"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_webhook_endpoint"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_webhook_endpoints"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_webhook_endpoints"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_webhook_endpoint"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_webhook_endpoint"(uuid, jsonb) TO "authenticated", "service_role";
