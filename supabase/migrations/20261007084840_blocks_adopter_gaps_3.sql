SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text);

DROP FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
  WITH time zone, timestamp WITH time zone, text, integer, boolean);

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := null;
    user_agent := null;
    session_id := null;
    request_id := null;
    scope := null;
  elsif actor_id is null then
    actor_id := auth.uid();
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."organization_id" is not distinct from audit_event.tenant
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
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_forget_dropped()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  delete from better_supabase.audited_tables a
  where a.target::oid in (
    select d.objid from pg_catalog.pg_event_trigger_dropped_objects() d
    where d.object_type = 'table'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.copy_comments (
  tenant    uuid,
  from_type text,
  from_id   text,
  to_type   text,
  to_id     text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  copied integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role copies comments' using errcode = '42501', hint = 'COMMENT_FORBIDDEN';
  end if;
  with copies as materialized (
    select y."id" as old_id, gen_random_uuid() as new_id
    from "better_supabase"."comments" y
    where y."organization_id" = copy_comments.tenant
      and y."subject_type" = copy_comments.from_type
      and y."subject_id" = copy_comments.from_id
  ), inserted as (
    insert into "better_supabase"."comments" ("id", "organization_id", "subject_type", "subject_id", "author_id", "body", "document", "mentions", "parent_id", "created_at", "edited_at", "deleted_at")
    select m.new_id, y."organization_id", copy_comments.to_type, copy_comments.to_id, y."author_id",
      y."body", y."document", '{}', p.new_id, y."created_at", y."edited_at", y."deleted_at"
    from "better_supabase"."comments" y
    join copies m on m.old_id = y."id"
    left join copies p on p.old_id = y."parent_id"
    order by y."created_at", y."id"
    returning 1
  )
  select count(*)::integer into copied from inserted;
  return copied;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_at           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_id           text                     DEFAULT NULL::text,
  max_items           integer                  DEFAULT 50,
  ascending           boolean                  DEFAULT false,
  skip                integer                  DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x.entry order by
    case when ascending then x.occurred_at end, case when ascending then x.id end,
    x.occurred_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'old', l."old_record", 'new', l."new_record", 'changed', l."changed", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."organization_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome") || jsonb_build_object('source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label", 'summary', l."summary", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope", 'metadata', l."metadata") as entry, l."occurred_at" as occurred_at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where (for_tenants is null or cardinality(for_tenants) = 0 or l."organization_id" = any (for_tenants))
      and (for_event_types is null or cardinality(for_event_types) = 0 or l."event_type" = any (for_event_types))
      and (for_actors is null or cardinality(for_actors) = 0 or l."actor_id" = any (for_actors))
      and (for_target_types is null or cardinality(for_target_types) = 0 or l."target_type" = any (for_target_types))
      and (for_records is null or cardinality(for_records) = 0 or l."record_id" = any (for_records))
      and (for_categories is null or cardinality(for_categories) = 0 or l."category" = any (for_categories))
      and (for_outcomes is null or cardinality(for_outcomes) = 0 or l."outcome" = any (for_outcomes))
      and (for_sources is null or cardinality(for_sources) = 0 or l."source" = any (for_sources))
      and (for_actor_kinds is null or cardinality(for_actor_kinds) = 0 or l."actor_kind" = any (for_actor_kinds))
      and (for_correlation_ids is null or cardinality(for_correlation_ids) = 0 or l."correlation_id" = any (for_correlation_ids))
      and (search is null or search = '' or concat_ws(' ', l."event_type", l."summary", l."target_label", l."actor_label", l."tenant_label", l."record_id", l."table_name") ilike '%' || replace(replace(replace(search, '\', '\\'), '%', '\%'), '_', '\_') || '%')
      and (since is null or l."occurred_at" >= since)
      and (until is null or l."occurred_at" < until)
      and (cursor_at is null or (
        case when ascending
          then (l."occurred_at", l."id"::text) > (cursor_at, coalesce(cursor_id, ''))
          else (l."occurred_at", l."id"::text) < (cursor_at, coalesce(cursor_id, ''))
        end))
    order by
      case when ascending then l."occurred_at" end, case when ascending then l."id"::text end,
      l."occurred_at" desc, l."id"::text desc
    limit least(greatest(coalesce(max_items, 50), 1), 1000)
    offset greatest(coalesce(skip, 0), 0)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unaudit (
  target text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  relation regclass := pg_catalog.to_regclass(unaudit.target);
begin
  if relation is not null then
    perform better_supabase.unaudit(relation);
  end if;
  delete from better_supabase.audited_tables a
  where not exists (select 1 from pg_catalog.pg_class c where c.oid = a.target::oid);
end;
$function$;

CREATE EVENT TRIGGER "bs_audit_forget_dropped"
  ON sql_drop
  WHEN TAG IN ('DROP SCHEMA', 'DROP TABLE')
  EXECUTE FUNCTION "better_supabase"."audit_forget_dropped"();

REVOKE ALL
  ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_forget_dropped"() FROM PUBLIC;

REVOKE ALL
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unaudit"(text) FROM PUBLIC;
