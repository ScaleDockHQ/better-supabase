SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text);

DROP FUNCTION "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid);

DROP FUNCTION "better_supabase"."edit_comment"(uuid, text, uuid[]);

DROP FUNCTION "better_supabase"."list_audit_events"(uuid, text, uuid, text, text, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, text, integer);

DROP FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer);

DROP FUNCTION "public"."search_notes"(extensions.vector, integer);

DROP FUNCTION "public"."search_notes_scores"(extensions.vector, integer);

CREATE TABLE "better_supabase"."platform_settings" (
  "key"        text                     NOT NULL,
  "value"      jsonb                    NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "platform_settings_key_check" CHECK ((key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'::text)),
  CONSTRAINT "platform_settings_pkey" PRIMARY KEY (key),
  "updated_by" uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."platform_settings"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."comments"
  ADD COLUMN "document" jsonb;

CREATE OR REPLACE FUNCTION better_supabase.audit (
  target          regclass,
  ignore          text[]   DEFAULT '{}'::text[],
  replace_trigger boolean  DEFAULT false,
  redact          text[]   DEFAULT '{}'::text[],
  category        text     DEFAULT NULL::text,
  event_prefix    text     DEFAULT NULL::text,
  target_type     text     DEFAULT NULL::text,
  tenant_column   text     DEFAULT NULL::text,
  label_column    text     DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  keys text[];
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bs_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  delete from better_supabase.audited_tables a where a.target = audit.target;
  execute format('drop trigger if exists bs_audit on %s', target);
  execute format(
    'create trigger bs_audit after insert or update or delete on %s for each row execute function better_supabase.audit_row_change(%L)',
    target,
    jsonb_strip_nulls(jsonb_build_object(
      'ignore', to_jsonb(coalesce(audit.ignore, '{}')),
      'redact', to_jsonb(coalesce(audit.redact, '{}')),
      'key_columns', to_jsonb(keys),
      'category', audit.category,
      'event_prefix', audit.event_prefix,
      'target_type', audit.target_type,
      'tenant_column', audit.tenant_column,
      'label_column', audit.label_column
    ))::text
  );
end;
$function$;

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
  session_id      text  DEFAULT NULL::text
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
    better_supabase.request_header('x-request-id'),
    coalesce(correlation_id, better_supabase.request_header('x-correlation-id')),
    case when tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
begin
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column
    into entry;
  else
    select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
      coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
      a.label_column
    into entry
    from (select 1) one
    left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~ '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  -- One change per column, values cut at 1000 characters, for revealing a
  -- single change without the whole rows.
  select jsonb_object_agg(k, jsonb_build_object(
    'old', case when length((old_row -> k)::text) > 1000 then to_jsonb(left((old_row -> k)::text, 1000)) else old_row -> k end,
    'new', case when length((new_row -> k)::text) > 1000 then to_jsonb(left((new_row -> k)::text, 1000)) else new_row -> k end
  ))
  into changed_values
  from unnest(coalesce(changed_columns, array(select jsonb_object_keys(coalesce(new_row, old_row))))) k;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    auth.uid(),
    coalesce(auth.jwt() ->> 'role', current_user),
    row_tenant,
    case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end,
    auth.jwt() -> 'act' ->> 'reason',
    case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email'),
    null,
    row_data ->> entry.label_column,
    null,
    better_supabase.request_header('x-request-id'),
    better_supabase.request_header('x-correlation-id'),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_schema (
  schema_name   text,
  tenant_column text,
  exempt        text[] DEFAULT '{}'::text[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  registered integer := 0;
  target regclass;
begin
  for target in
    select format('%I.%I', n.nspname, c.relname)::regclass
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = schema_name
      and c.relkind in ('r', 'p')
      and not c.relispartition
      and exists (
        select 1 from pg_catalog.pg_attribute a
        where a.attrelid = c.oid and a.attname = audit_schema.tenant_column and a.attnum > 0 and not a.attisdropped
      )
      and not exists (select 1 from unnest(exempt) e where c.relname like e)
      and not exists (
        select 1 from pg_catalog.pg_trigger t where t.tgrelid = c.oid and t.tgname = 'bs_audit'
      )
    order by c.relname
  loop
    perform better_supabase.audit(target);
    registered := registered + 1;
  end loop;
  return registered;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_settings (
  target regclass
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(
    (select convert_from(substring(t.tgargs from 1 for position('\x00'::bytea in t.tgargs) - 1), 'utf8')::jsonb
     from pg_catalog.pg_trigger t
     where t.tgrelid = audit_settings.target and t.tgname = 'bs_audit' and t.tgnargs > 0),
    (select jsonb_strip_nulls(jsonb_build_object(
       'ignore', to_jsonb(a.ignore), 'redact', to_jsonb(a.redact), 'key_columns', to_jsonb(a.key_columns),
       'category', a.category, 'event_prefix', a.event_prefix, 'target_type', a.target_type,
       'tenant_column', a.tenant_column, 'label_column', a.label_column))
     from better_supabase.audited_tables a where a.target = audit_settings.target)
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_rate_limit (
  scope        text,
  key          text,
  max_requests integer  DEFAULT NULL::integer,
  period       interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select to_jsonb(h) from better_supabase.hit_rate_limit(scope, key, max_requests, period) h
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_request()
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule better_supabase.rate_limit_rules;
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from better_supabase.rate_limit_rules r where r.scope in ('*', path) order by r.scope
  loop
    caller := coalesce(
      claims ->> rule.key_claim,
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
    values (rule.scope, caller, now(), 1)
    on conflict on constraint rate_limits_pkey do update set
      window_start = case when l.window_start + rule.period <= now() then now() else l.window_start end,
      hits = case when l.window_start + rule.period <= now() then 1 else l.hits + 1 end
    returning l.hits, l.window_start into used, started;
    if used > rule.max_requests then
      retry := greatest(1, ceil(extract(epoch from started + rule.period - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule.scope, rule.max_requests, rule.period),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_counts (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(x.subject_id, x.n), '{}'::jsonb)
  from (
    select y."subject_id" as subject_id, count(*) as n
    from "better_supabase"."comments" y
    where y."organization_id" = comment_counts.tenant
      and y."subject_type" = comment_counts.subject_type
      and y."subject_id" = any (comment_counts.subject_ids)
      and y."deleted_at" is null
    group by 1
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_before_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'UPDATE' and old."deleted_at" is not null then
    raise exception 'This comment was deleted' using errcode = 'P0001', hint = 'COMMENT_DELETED';
  end if;
  if new."deleted_at" is not null then
    new."body" := '';
    new."document" := null;
    new."mentions" := '{}';
    return new;
  end if;
  new."mentions" := array(
    select distinct x from unnest(new."mentions") x
    where x is not null and x is distinct from new."author_id"
    order by x
  );
  if tg_op = 'INSERT' and new."parent_id" is not null and not exists (
    select 1 from "better_supabase"."comments" p
    where p."id" = new."parent_id" and p."organization_id" = new."organization_id"
      and p."subject_type" = new."subject_type" and p."subject_id" = new."subject_id"
  ) then
    raise exception 'A reply must be on its parent''s subject' using errcode = '23514', hint = 'COMMENT_PARENT_MISMATCH';
  end if;
  if tg_op = 'UPDATE' and (new."body" is distinct from old."body" or new."document" is distinct from old."document" or new."mentions" is distinct from old."mentions") then
    if old."author_id" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
      raise exception 'Only the author edits a comment' using errcode = '42501', hint = 'COMMENT_NOT_AUTHOR';
    end if;
    new."edited_at" := now();
  end if;
  return new;
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
  create temporary table if not exists bs_comment_copy (old_id uuid primary key, new_id uuid not null) on commit drop;
  delete from bs_comment_copy where old_id is not null;
  insert into bs_comment_copy (old_id, new_id)
  select y."id", gen_random_uuid()
  from "better_supabase"."comments" y
  where y."organization_id" = copy_comments.tenant
    and y."subject_type" = copy_comments.from_type
    and y."subject_id" = copy_comments.from_id;
  insert into "better_supabase"."comments" ("id", "organization_id", "subject_type", "subject_id", "author_id", "body", "document", "mentions", "parent_id", "created_at", "edited_at", "deleted_at")
  select m.new_id, y."organization_id", copy_comments.to_type, copy_comments.to_id, y."author_id",
    y."body", y."document", '{}', p.new_id, y."created_at", y."edited_at", y."deleted_at"
  from "better_supabase"."comments" y
  join bs_comment_copy m on m.old_id = y."id"
  left join bs_comment_copy p on p.old_id = y."parent_id"
  order by y."created_at", y."id";
  get diagnostics copied = row_count;
  return copied;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.count_audit_events (
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
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select count(*) from "better_supabase"."audit_events" l
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_api_key (
  name        text,
  public_id   text,
  secret_hash text,
  tenant      uuid                     DEFAULT NULL::uuid,
  personal    boolean                  DEFAULT false,
  scopes      text[]                   DEFAULT '{}'::text[],
  expires_at  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  rate_limit  integer                  DEFAULT NULL::integer,
  prefix      text                     DEFAULT 'bs'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  owner uuid := case when personal then auth.uid() end;
  created "better_supabase"."api_keys";
begin
  if personal and owner is null then
    raise exception 'Sign in to create a personal API key' using errcode = '42501', hint = 'API_KEY_SIGN_IN';
  end if;
  if not personal and tenant is null then
    raise exception 'A tenant API key needs a tenant' using errcode = '22023', hint = 'API_KEY_TENANT_REQUIRED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if not personal and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.manage'), false) then
      raise exception 'Not allowed to manage API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is not null and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.own'), false) then
      raise exception 'Not allowed to create API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
  end if;
  if expires_at is not null and expires_at <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at")
  values (tenant, owner, create_api_key.name, create_api_key.prefix, create_api_key.public_id, create_api_key.secret_hash, coalesce(create_api_key.scopes, '{}'), create_api_key.rate_limit, create_api_key.expires_at)
  returning * into created;
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_comment (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  body         text,
  mentions     uuid[] DEFAULT '{}'::uuid[],
  parent       uuid   DEFAULT NULL::uuid,
  document     jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."comments" as x ("organization_id", "subject_type", "subject_id", "body", "document", "mentions", "parent_id")
  values (create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body, create_comment.document, coalesce(create_comment.mentions, '{}'), create_comment.parent)
  returning to_jsonb(x.*)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_comment (
  id             uuid,
  body           text,
  mentions       uuid[]  DEFAULT NULL::uuid[],
  document       jsonb   DEFAULT NULL::jsonb,
  clear_document boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  update "better_supabase"."comments" x
  set "body" = edit_comment.body,
      "document" = case
        when coalesce(edit_comment.clear_document, false) then null
        else coalesce(edit_comment.document, x."document")
      end,
      "mentions" = coalesce(edit_comment.mentions, x."mentions")
  where x."id" = edit_comment.id
  returning to_jsonb(x.*)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_platform_settings()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."platform_settings" s
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."occurred_at" desc, x."id" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit least(greatest(coalesce(list_activity.max_rows, 50), 1), 500)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_api_keys (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', k."id",
    'organization_id', k."organization_id",
    'user_id', k."user_id",
    'name', k."name",
    'prefix', k."prefix",
    'public_id', k."public_id",
    'scopes', to_jsonb(k."scopes"),
    'rate_limit', k."rate_limit",
    'expires_at', k."expires_at",
    'last_used_at', k."last_used_at",
    'revoked_at', k."revoked_at",
    'rotated_from', k."rotated_from",
    'created_by', k."created_by",
    'created_at', k."created_at"
  ) order by k."created_at" desc), '[]'::jsonb)
  from "better_supabase"."api_keys" k
  where case
    when list_api_keys.tenant is null then k."user_id" = auth.uid()
    when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_api_keys.tenant, 'api_keys.manage'), false) then k."organization_id" = list_api_keys.tenant
    else k."organization_id" = list_api_keys.tenant and k."user_id" = auth.uid()
  end
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
  ascending           boolean                  DEFAULT false
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
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100,
  skip         integer                  DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."created_at", x."id"), '[]'::jsonb)
  from (
    select * from "better_supabase"."comments" y
    where y."organization_id" = list_comments.tenant
      and y."subject_type" = list_comments.subject_type
      and y."subject_id" = list_comments.subject_id
      and (list_comments.after is null or y."created_at" > list_comments.after)
    order by y."created_at", y."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_activity (
  batch jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_platform_setting (
  key text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with removed as (
    delete from "better_supabase"."platform_settings" s where s."key" = reset_platform_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_api_key (
  key uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  found "better_supabase"."api_keys";
begin
  select * into found from "better_supabase"."api_keys" k where k."id" = revoke_api_key.key;
  if found."id" is null or not ((found."organization_id" is not null and coalesce(better_supabase.can('tenant', found."organization_id", 'api_keys.manage'), false)) or coalesce(found."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  update "better_supabase"."api_keys" k set "revoked_at" = now()
  where k."id" = found."id" and (k."revoked_at" is null or k."revoked_at" > now());
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_api_key (
  key         uuid,
  public_id   text,
  secret_hash text,
  grace       interval DEFAULT '1 day'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  old "better_supabase"."api_keys";
  created "better_supabase"."api_keys";
begin
  select * into old from "better_supabase"."api_keys" k where k."id" = rotate_api_key.key for update;
  if old."id" is null or not ((old."organization_id" is not null and coalesce(better_supabase.can('tenant', old."organization_id", 'api_keys.manage'), false)) or coalesce(old."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  if old."revoked_at" is not null and old."revoked_at" <= now() then
    raise exception 'A revoked API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_REVOKED';
  end if;
  if grace is null or grace < interval '0' then
    raise exception 'grace must be zero or more' using errcode = '22023', hint = 'API_KEY_GRACE';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at", "rotated_from")
  values (old."organization_id", old."user_id", old."name", old."prefix", rotate_api_key.public_id, rotate_api_key.secret_hash, old."scopes", old."rate_limit", old."expires_at", old."id")
  returning * into created;
  update "better_supabase"."api_keys" k set "revoked_at" = now() + grace where k."id" = old."id";
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_organization_setting (
  tenant uuid,
  key    text,
  value  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."organization_settings" ("organization_id", "key", "value", "updated_by", "updated_at")
  values (set_organization_setting.tenant, set_organization_setting.key, coalesce(set_organization_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict ("organization_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_platform_setting (
  key   text,
  value jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."platform_settings" ("key", "value", "updated_by", "updated_at")
  values (set_platform_setting.key, coalesce(set_platform_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict ("key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_user_setting (
  key   text,
  value jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."user_settings" ("user_id", "key", "value", "updated_by", "updated_at")
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb), auth.uid(), now())
  on conflict ("user_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$function$;

CREATE OR REPLACE FUNCTION public.search_notes (
  query extensions.vector,
  k     integer           DEFAULT 10
)
  RETURNS SETOF public.notes
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
begin
  perform set_config('hnsw.iterative_scan', 'strict_order', true);
  return query select t.* from "public"."notes" t
  where t."embedding" is not null
  order by t."embedding" operator(extensions.<=>) query
  limit least(greatest(k, 1), 1000);
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."search_notes"(extensions.vector, integer) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.search_notes_scores (
  query extensions.vector,
  k     integer           DEFAULT 10
)
  RETURNS TABLE (
    id    jsonb,
    score double precision
  )
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
begin
  perform set_config('hnsw.iterative_scan', 'strict_order', true);
  return query select to_jsonb(r.id), r.score from (
  with vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) query as distance
    from "public"."notes" t
    where t."embedding" is not null
    order by t."embedding" operator(extensions.<=>) query
    limit least(greatest(k, 1), 1000)
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  fused as (
    select v.id, 1 - v.distance as score from vector_ranked v
  )
  select f.id, f.score::double precision as score, row_number() over (order by f.score::double precision desc) as ord from fused f
  order by ord
  limit least(greatest(k, 1), 1000)
  ) r
  order by r.ord;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) FROM PUBLIC, "anon";

CREATE POLICY "platform_settings_delete" ON "better_supabase"."platform_settings"
  FOR DELETE
  TO "authenticated"
  USING (COALESCE(better_supabase.is_platform('settings.manage'::text), false));

CREATE POLICY "platform_settings_insert" ON "better_supabase"."platform_settings"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (COALESCE(better_supabase.is_platform('settings.manage'::text), false));

CREATE POLICY "platform_settings_read_public" ON "better_supabase"."platform_settings"
  FOR SELECT
  TO "anon"
  USING (false);

CREATE POLICY "platform_settings_read" ON "better_supabase"."platform_settings"
  FOR SELECT
  TO "authenticated"
  USING (true);

CREATE POLICY "platform_settings_update" ON "better_supabase"."platform_settings"
  FOR UPDATE
  TO "authenticated"
  USING (COALESCE(better_supabase.is_platform('settings.manage'::text), false))
  WITH CHECK (COALESCE(better_supabase.is_platform('settings.manage'::text), false));

REVOKE ALL
  ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_settings"(regclass) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."check_rate_limit"(text, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."check_rate_limit"(text, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."comment_counts"(uuid, text, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."comment_counts"(uuid, text, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."copy_comments"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."copy_comments"(uuid, text, text, text, text) TO "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."edit_comment"(uuid, text, uuid[], jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."edit_comment"(uuid, text, uuid[], jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_platform_settings"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_platform_settings"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reset_platform_setting"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reset_platform_setting"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_platform_setting"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_platform_setting"(text, jsonb) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."search_notes"(extensions.vector, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."search_notes"(extensions.vector, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_notes"(extensions.vector, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_notes"(extensions.vector, integer) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."search_notes_scores"(extensions.vector, integer) TO "service_role";

REVOKE ALL ("document") ON TABLE "better_supabase"."comments" FROM "authenticated";

GRANT INSERT ("document"), UPDATE ("document") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT SELECT ON TABLE "better_supabase"."platform_settings" TO "anon";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "better_supabase"."platform_settings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."platform_settings" TO "service_role";

ALTER TABLE "better_supabase"."platform_settings"
  ADD CONSTRAINT "platform_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX platform_settings_updated_by_idx ON better_supabase.platform_settings USING btree (updated_by);
