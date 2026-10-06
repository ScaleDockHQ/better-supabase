SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."activity_entries" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "event_id"        text                     NOT NULL,
  "type"            text                     NOT NULL,
  "actor_id"        uuid,
  "subject_type"    text,
  "subject_id"      text,
  "summary"         text,
  "data"            jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "occurred_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "activity_entries_event_id_key" UNIQUE (event_id),
  CONSTRAINT "activity_entries_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."activity_entries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."api_keys" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid,
  "user_id"         uuid,
  "name"            text                     NOT NULL,
  "prefix"          text                     NOT NULL,
  "public_id"       text                     NOT NULL,
  "secret_hash"     text                     NOT NULL,
  "scopes"          text[]                   NOT NULL DEFAULT '{}'::text[],
  "rate_limit"      integer,
  "window_start"    timestamp with time zone,
  "window_hits"     integer                  NOT NULL DEFAULT 0,
  "expires_at"      timestamp with time zone,
  "last_used_at"    timestamp with time zone,
  "revoked_at"      timestamp with time zone,
  "rotated_from"    uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "api_keys_check" CHECK (((organization_id IS NOT NULL) OR (user_id IS NOT NULL))),
  CONSTRAINT "api_keys_name_check" CHECK ((length(TRIM(BOTH FROM name)) > 0)),
  CONSTRAINT "api_keys_pkey" PRIMARY KEY (id),
  CONSTRAINT "api_keys_prefix_check" CHECK ((prefix ~ '^[a-z][a-z0-9]*$'::text)),
  CONSTRAINT "api_keys_public_id_check" CHECK ((public_id ~ '^[0-9a-f]{16}$'::text)),
  CONSTRAINT "api_keys_public_id_key" UNIQUE (public_id),
  CONSTRAINT "api_keys_rate_limit_check" CHECK ((rate_limit > 0)),
  CONSTRAINT "api_keys_secret_hash_check" CHECK ((secret_hash ~ '^[0-9a-f]{64}$'::text)),
  "created_by"      uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."api_keys"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."audit_events" (
  "id"                   bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "table_name"           text,
  "record_id"            text,
  "op"                   text                     NOT NULL,
  "old_record"           jsonb,
  "new_record"           jsonb,
  "changed"              text[],
  "actor_id"             uuid,
  "actor_role"           text,
  "organization_id"      uuid,
  "occurred_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "impersonated_by"      uuid,
  "impersonation_reason" text,
  "support_session_id"   uuid,
  "event_type"           text,
  "category"             text,
  "outcome"              text,
  "source"               text,
  "target_type"          text,
  "metadata"             jsonb,
  "idempotency_key"      text,
  "actor_kind"           text,
  "actor_label"          text,
  "tenant_label"         text,
  "target_label"         text,
  "summary"              text,
  "request_id"           text,
  "correlation_id"       text,
  "scope"                text,
  CONSTRAINT "audit_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "bs_audit_op_check" CHECK ((op = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text, 'event'::text])))
);

ALTER TABLE "better_supabase"."audit_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."audited_tables" (
  "target"        regclass NOT NULL,
  "ignore"        text[]   NOT NULL DEFAULT '{}'::text[],
  "key_columns"   text[]   NOT NULL DEFAULT '{id}'::text[],
  "redact"        text[]   NOT NULL DEFAULT '{}'::text[],
  "category"      text,
  "event_prefix"  text,
  "target_type"   text,
  "tenant_column" text,
  "label_column"  text,
  CONSTRAINT "audited_tables_pkey" PRIMARY KEY (target)
);

ALTER TABLE "better_supabase"."audited_tables"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."comments" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "subject_type"    text                     NOT NULL,
  "subject_id"      text                     NOT NULL,
  "body"            text                     NOT NULL,
  "mentions"        uuid[]                   NOT NULL DEFAULT '{}'::uuid[],
  "parent_id"       uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "edited_at"       timestamp with time zone,
  "deleted_at"      timestamp with time zone,
  CONSTRAINT "comments_body_check" CHECK ((length(body) <= 10000)),
  CONSTRAINT "comments_check" CHECK (((deleted_at IS NOT NULL) OR (length(btrim(body)) > 0))),
  CONSTRAINT "comments_pkey" PRIMARY KEY (id),
  CONSTRAINT "comments_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200))),
  CONSTRAINT "comments_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  "author_id"       uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."comments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."organization_settings" (
  "organization_id" uuid                     NOT NULL,
  "key"             text                     NOT NULL,
  "value"           jsonb                    NOT NULL,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "organization_settings_key_check" CHECK ((key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'::text)),
  CONSTRAINT "organization_settings_pkey" PRIMARY KEY (organization_id, key),
  "updated_by"      uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."organization_settings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."user_settings" (
  "user_id"    uuid                     NOT NULL,
  "key"        text                     NOT NULL,
  "value"      jsonb                    NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "user_settings_key_check" CHECK ((key ~ '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$'::text)),
  CONSTRAINT "user_settings_pkey" PRIMARY KEY (user_id, key),
  "updated_by" uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."user_settings"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.api_key_tenant()
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select nullif(auth.jwt() -> 'api_key' ->> 'organization_id', '')::uuid
$function$;

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
  insert into better_supabase.audited_tables as a
    (target, ignore, key_columns, redact, category, event_prefix, target_type, tenant_column, label_column)
  values (
    audit.target, audit.ignore, coalesce(keys, '{id}'), audit.redact, audit.category,
    audit.event_prefix, audit.target_type, audit.tenant_column, audit.label_column
  )
  on conflict on constraint audited_tables_pkey do update
    set ignore = excluded.ignore, key_columns = excluded.key_columns, redact = excluded.redact,
      category = excluded.category, event_prefix = excluded.event_prefix,
      target_type = excluded.target_type, tenant_column = excluded.tenant_column,
      label_column = excluded.label_column;
  execute format('drop trigger if exists bs_audit on %s', target);
  execute format(
    'create trigger bs_audit after insert or update or delete on %s for each row execute function better_supabase.audit_row_change()',
    target
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE'
    and current_setting('better_supabase.audit_purge', true) = 'on'
    and current_user = (
      select r.rolname from pg_catalog.pg_proc p
      join pg_catalog.pg_roles r on r.oid = p.proowner
      where p.oid = to_regprocedure('better_supabase.purge_audit_log(interval, integer, uuid, boolean)')
    )
  then
    return old;
  end if;
  raise exception 'audit log entries are append-only'
    using errcode = '42501', hint = 'Delete old entries with better_supabase.purge_audit_log()';
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
  correlation_id  text  DEFAULT NULL::text
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
  if restricted is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set sql.modules.audit.options.restricted to true.';
  end if;
  if not (coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) or actor_id is null then
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

CREATE OR REPLACE FUNCTION better_supabase.audit_events_tenants (
  older_than interval DEFAULT '1 day'::interval
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select distinct l."organization_id" from "better_supabase"."audit_events" l
  where l."occurred_at" < now() - older_than
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
begin
  select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
    coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
    a.label_column
  into entry
  from (select 1) one
  left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
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
        select 1 from better_supabase.audited_tables t where t.target = format('%I.%I', n.nspname, c.relname)::regclass
      )
    order by c.relname
  loop
    perform better_supabase.audit(target);
    registered := registered + 1;
  end loop;
  return registered;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_schema_calls (
  schema_name   text,
  tenant_column text,
  exempt        text[] DEFAULT '{}'::text[]
)
  RETURNS SETOF text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select format('select better_supabase.audit(%L);', format('%I.%I', n.nspname, c.relname))
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = schema_name
    and c.relkind in ('r', 'p')
    and not c.relispartition
    and exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = c.oid and a.attname = tenant_column and a.attnum > 0 and not a.attisdropped
    )
    and not exists (select 1 from unnest(exempt) e where c.relname like e)
  order by c.relname
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
  SET search_path TO ''
  AS $function$
  select auth.uid() is not null and better_supabase.can_user(auth.uid(), scope, scope_id, permission)
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
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or better_supabase.organization_member_role(tenant, auth.uid()) = 'admin'
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
  select coalesce(
    scope = 'tenant'
      and r.role is not null
      and (r.role = 'admin' or permission = any (array[
        'comments.read', 'comments.create', 'activity.read', 'api_keys.own', 'settings.read'
      ])),
    false
  )
  from (select better_supabase.organization_member_role(scope_id, member) as role) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select true
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_after_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."deleted_at" is not null then
    null;
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
  );
  if tg_op = 'INSERT' then
    null;
  end if;
  if cardinality(v_new) > 0 then
    null;
  end if;
  return null;
end;
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
  if tg_op = 'UPDATE' and (new."body" is distinct from old."body" or new."mentions" is distinct from old."mentions") then
    if old."author_id" is distinct from auth.uid() and not (coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
      raise exception 'Only the author edits a comment' using errcode = '42501', hint = 'COMMENT_NOT_AUTHOR';
    end if;
    new."edited_at" := now();
  end if;
  return new;
end;
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
  if not (coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
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
  parent       uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."comments" as x ("organization_id", "subject_type", "subject_id", "body", "mentions", "parent_id")
  values (create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body, coalesce(create_comment.mentions, '{}'), create_comment.parent)
  returning to_jsonb(x.*)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_comment (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with removed as (
    update "better_supabase"."comments" x set "deleted_at" = now()
    where x."id" = delete_comment.id and x."deleted_at" is null
    returning 1
  )
  select exists (select 1 from removed)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_comment (
  id       uuid,
  body     text,
  mentions uuid[] DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  update "better_supabase"."comments" x
  set "body" = edit_comment.body,
      "mentions" = coalesce(edit_comment.mentions, x."mentions")
  where x."id" = edit_comment.id
  returning to_jsonb(x.*)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_organization_settings (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."organization_settings" s
  where s."organization_id" = get_organization_settings.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_user_settings()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(s."key", s."value"), '{}'::jsonb)
  from "better_supabase"."user_settings" s
  where s."user_id" = auth.uid()
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
  select coalesce(r.role is not null and (roles is null or r.role = any (roles)), false)
  from (select better_supabase.organization_member_role(organization, auth.uid()) as role) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.has_scope (
  scope text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when auth.jwt() -> 'api_key' is null then true
    else coalesce(auth.jwt() -> 'api_key' -> 'scopes', '[]'::jsonb) ?| array['*', has_scope.scope]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.is_platform (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select false
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
    when coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_api_keys.tenant, 'api_keys.manage'), false) then k."organization_id" = list_api_keys.tenant
    else k."organization_id" = list_api_keys.tenant and k."user_id" = auth.uid()
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_audit_events (
  for_tenant      uuid                     DEFAULT NULL::uuid,
  for_event_type  text                     DEFAULT NULL::text,
  for_actor       uuid                     DEFAULT NULL::uuid,
  for_target_type text                     DEFAULT NULL::text,
  for_record      text                     DEFAULT NULL::text,
  since           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id       text                     DEFAULT NULL::text,
  max_items       integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x.entry order by x.occurred_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'old', l."old_record", 'new', l."new_record", 'changed', l."changed", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."organization_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome") || jsonb_build_object('source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label", 'summary', l."summary", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope", 'metadata', l."metadata") as entry, l."occurred_at" as occurred_at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where (for_tenant is null or l."organization_id" = for_tenant)
    and (for_event_type is null or l."event_type" = for_event_type)
    and (for_actor is null or l."actor_id" = for_actor)
    and (for_target_type is null or l."target_type" = for_target_type)
    and (for_record is null or l."record_id" = for_record)
      and (since is null or l."occurred_at" >= since)
      and (until is null or l."occurred_at" < until)
      and (before_at is null or (l."occurred_at", l."id"::text) < (before_at, coalesce(before_id, '')))
    order by l."occurred_at" desc, l."id"::text desc
    limit least(greatest(coalesce(max_items, 50), 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100
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
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.member_organization_ids (
  roles text[] DEFAULT NULL::text[]
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select t.id
  from (select better_supabase.current_tenant_id() as id) t
  cross join lateral (select better_supabase.organization_member_role(t.id, auth.uid()) as role) r
  where r.role is not null and (roles is null or r.role = any (roles))
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
  select coalesce(jsonb_agg(jsonb_build_object('scope', 'tenant', 'id', t.id, 'roles', jsonb_build_array(r.role))), '[]'::jsonb)
  from (
    select nullif(u.raw_app_meta_data ->> 'tenant_id', '')::uuid as id
    from auth.users u
    where u.id = membership_claims.user_id
  ) t
  cross join lateral (select better_supabase.organization_member_role(t.id, membership_claims.user_id) as role) r
  where r.role is not null
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
  select coalesce(ur.role::text, 'member')
  from auth.users u
  left join rbac.user_roles ur on ur.user_id = u.id
  where u.id = member
    and nullif(u.raw_app_meta_data ->> 'tenant_id', '') = organization::text
$function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_claims (
  user_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select '{}'::jsonb
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_audit_log (
  older_than interval DEFAULT '1 year'::interval,
  batch      integer  DEFAULT 10000,
  tenant     uuid     DEFAULT NULL::uuid,
  for_tenant boolean  DEFAULT false
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  purged integer;
begin
  perform set_config('better_supabase.audit_purge', 'on', true);
  if not for_tenant and to_regprocedure('"public"."audit_retention"(uuid)') is not null then
    -- Not a literal name, so plpgsql_check passes without the hook.
    execute format(
      'with gone as (
      delete from "better_supabase"."audit_events"
      where "id" in (
        select l."id" from "better_supabase"."audit_events" l
        where l."occurred_at" < now() - coalesce(%s(l."organization_id"), $1)
        order by l."occurred_at"
        limit $2
      )
      returning 1
    )
    select count(*)::integer from gone',
      to_regprocedure('"public"."audit_retention"(uuid)')::oid::regproc
    ) into purged using older_than, batch;
  else
    with gone as (
      delete from "better_supabase"."audit_events"
      where "id" in (
        select l."id" from "better_supabase"."audit_events" l
        where l."occurred_at" < now() - older_than
          and (not for_tenant or l."organization_id" is not distinct from purge_audit_log.tenant)
        order by l."occurred_at"
        limit batch
      )
      returning 1
    )
    select count(*)::integer into purged from gone;
  end if;
  perform set_config('better_supabase.audit_purge', 'off', true);
  return purged;
end;
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
  if not (coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
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

CREATE OR REPLACE FUNCTION better_supabase.request_header (
  name text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb ->> request_header.name;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_ip()
  RETURNS inet
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return nullif(trim(reverse(split_part(reverse(current_setting('request.headers', true)::json ->> 'x-forwarded-for'), ',', 1))), '')::inet;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_organization_setting (
  tenant uuid,
  key    text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with removed as (
    delete from "better_supabase"."organization_settings" s
    where s."organization_id" = reset_organization_setting.tenant and s."key" = reset_organization_setting.key
    returning 1
  )
  select exists (select 1 from removed)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_user_setting (
  key text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with removed as (
    delete from "better_supabase"."user_settings" s where s."user_id" = auth.uid() and s."key" = reset_user_setting.key
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
  if found."id" is null or not ((found."organization_id" is not null and coalesce(better_supabase.can('tenant', found."organization_id", 'api_keys.manage'), false)) or coalesce(found."user_id" = auth.uid(), false) or coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
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
  if old."id" is null or not ((old."organization_id" is not null and coalesce(better_supabase.can('tenant', old."organization_id", 'api_keys.manage'), false)) or coalesce(old."user_id" = auth.uid(), false) or coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
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
  insert into "better_supabase"."organization_settings" ("organization_id", "key", "value")
  values (set_organization_setting.tenant, set_organization_setting.key, coalesce(set_organization_setting.value -> 'value', 'null'::jsonb))
  on conflict ("organization_id", "key") do update
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
  insert into "better_supabase"."user_settings" ("user_id", "key", "value")
  values (auth.uid(), set_user_setting.key, coalesce(set_user_setting.value -> 'value', 'null'::jsonb))
  on conflict ("user_id", "key") do update
    set "value" = excluded."value", "updated_by" = auth.uid(), "updated_at" = now()
  returning "value"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_disabled (
  tenant uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select false
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tenant_ids_with (
  permission text
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select t.id
  from (select better_supabase.current_tenant_id() as id) t
  where better_supabase.can('tenant', t.id, permission)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unaudit (
  target regclass
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  execute format('drop trigger if exists bs_audit on %s', target);
  delete from better_supabase.audited_tables a where a.target = unaudit.target;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.user_disabled (
  user_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select false
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_api_key (
  public_id   text,
  secret_hash text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  found "better_supabase"."api_keys";
  started timestamptz;
  hits integer;
begin
  select * into found from "better_supabase"."api_keys" k where k."public_id" = verify_api_key.public_id;
  if found."id" is null
    or found."secret_hash" <> verify_api_key.secret_hash
    or (found."expires_at" is not null and found."expires_at" <= now())
    or (found."revoked_at" is not null and found."revoked_at" <= now())
    or (found."user_id" is not null and better_supabase.user_disabled(found."user_id"))
    or (found."organization_id" is not null and better_supabase.tenant_disabled(found."organization_id"))
    or (found."user_id" is not null and found."organization_id" is not null
      and better_supabase.organization_member_role(found."organization_id", found."user_id") is null)
  then
    return jsonb_build_object('status', 'invalid');
  end if;
  if found."rate_limit" is not null then
    update "better_supabase"."api_keys" k set
      "window_start" = case when k."window_start" is null or k."window_start" + interval '1 minute' <= now() then now() else k."window_start" end,
      "window_hits" = case when k."window_start" is null or k."window_start" + interval '1 minute' <= now() then 1 else k."window_hits" + 1 end
    where k."id" = found."id"
    returning k."window_start", k."window_hits" into started, hits;
    if hits > found."rate_limit" then
      return jsonb_build_object(
        'status', 'rate_limited',
        'retry_after', greatest(1, ceil(extract(epoch from started + interval '1 minute' - now()))::integer)
      );
    end if;
  end if;
  if found."last_used_at" is null or found."last_used_at" + interval '60 seconds' <= now() then
    update "better_supabase"."api_keys" k set "last_used_at" = now() where k."id" = found."id";
  end if;
  return jsonb_build_object('status', 'ok', 'key', jsonb_build_object(
    'id', found."id",
    'organization_id', found."organization_id",
    'user_id', found."user_id",
    'name', found."name",
    'prefix', found."prefix",
    'public_id', found."public_id",
    'scopes', to_jsonb(found."scopes"),
    'rate_limit', found."rate_limit",
    'expires_at', found."expires_at",
    'last_used_at', found."last_used_at",
    'revoked_at', found."revoked_at",
    'rotated_from', found."rotated_from",
    'created_by', found."created_by",
    'created_at', found."created_at"
  ));
end;
$function$;

ALTER TABLE "better_supabase"."activity_entries"
  ADD CONSTRAINT "activity_entries_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."api_keys"
  ADD CONSTRAINT "api_keys_rotated_from_fkey" FOREIGN KEY (rotated_from) REFERENCES better_supabase.api_keys(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."api_keys"
  ADD CONSTRAINT "api_keys_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."comments"
  ADD CONSTRAINT "comments_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES better_supabase.comments(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."user_settings"
  ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE VIEW "better_supabase"."audit_log" WITH (security_invoker=true) AS  SELECT id,
    table_name,
    record_id,
    op,
    old_record,
    new_record,
    changed,
    actor_id,
    actor_role,
    organization_id,
    occurred_at,
    impersonated_by,
    impersonation_reason,
    support_session_id,
    event_type,
    category,
    outcome,
    source,
    target_type,
    metadata,
    idempotency_key,
    actor_kind,
    actor_label,
    tenant_label,
    target_label,
    summary,
    request_id,
    correlation_id,
    scope,
    occurred_at AS at,
    organization_id AS org_id
   FROM better_supabase.audit_events l;

CREATE INDEX activity_entries_actor_idx ON better_supabase.activity_entries USING btree (actor_id);

CREATE INDEX activity_entries_feed_idx ON better_supabase.activity_entries USING btree (organization_id, occurred_at DESC, id DESC);

CREATE INDEX activity_entries_subject_idx ON better_supabase.activity_entries USING btree (organization_id, subject_type, subject_id);

CREATE INDEX api_keys_rotated_from_idx ON better_supabase.api_keys USING btree (rotated_from);

CREATE INDEX api_keys_tenant_idx ON better_supabase.api_keys USING btree (organization_id);

CREATE INDEX api_keys_user_idx ON better_supabase.api_keys USING btree (user_id);

CREATE UNIQUE INDEX audit_events_idempotency_idx ON better_supabase.audit_events USING btree (idempotency_key, organization_id) NULLS NOT DISTINCT
  WHERE (idempotency_key IS NOT NULL);

CREATE INDEX audit_events_occurred_at_idx ON better_supabase.audit_events USING btree (occurred_at);

CREATE INDEX audit_events_organization_idx ON better_supabase.audit_events USING btree (organization_id, occurred_at DESC);

CREATE INDEX audit_events_record_idx ON better_supabase.audit_events USING btree (table_name, record_id, occurred_at DESC);

CREATE INDEX comments_parent_idx ON better_supabase.comments USING btree (parent_id);

CREATE INDEX comments_subject_idx ON better_supabase.comments USING btree (organization_id, subject_type, subject_id, created_at);

CREATE TRIGGER bs_audit_append_only
  BEFORE DELETE OR UPDATE ON better_supabase.audit_events
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_append_only();

CREATE TRIGGER bs_audit_no_truncate
  BEFORE TRUNCATE ON better_supabase.audit_events
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.audit_append_only();

CREATE TRIGGER bs_comments_after_write
  AFTER INSERT OR UPDATE OF mentions, deleted_at ON better_supabase.comments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_after_write();

CREATE TRIGGER bs_comments_before_write
  BEFORE INSERT OR UPDATE ON better_supabase.comments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_before_write();

CREATE POLICY "activity_entries_read" ON "better_supabase"."activity_entries"
  FOR SELECT
  TO "authenticated"
  USING (COALESCE(better_supabase.can('tenant'::text, organization_id, 'activity.read'::text), false));

CREATE POLICY "comments_read" ON "better_supabase"."comments"
  FOR SELECT
  TO "authenticated"
  USING
    ((COALESCE(better_supabase.can('tenant'::text, organization_id, 'comments.read'::text), false) AND better_supabase.comment_subject_readable(subject_type, subject_id,
    organization_id)));

CREATE POLICY "organization_settings_delete" ON "better_supabase"."organization_settings"
  FOR DELETE
  TO "authenticated"
  USING
    (((COALESCE(NULLIF((auth.jwt() ->> 'role'::text), ''::text), (SESSION_USER)::text) = ANY (ARRAY['service_role'::text, 'postgres'::text, 'supabase_admin'::text])) OR
    COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false)));

CREATE POLICY "organization_settings_insert" ON "better_supabase"."organization_settings"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((COALESCE(NULLIF((auth.jwt() ->> 'role'::text), ''::text), (SESSION_USER)::text) = ANY (ARRAY['service_role'::text, 'postgres'::text, 'supabase_admin'::text])) OR
    COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false)));

CREATE POLICY "organization_settings_read" ON "better_supabase"."organization_settings"
  FOR SELECT
  TO "authenticated"
  USING
    (((COALESCE(NULLIF((auth.jwt() ->> 'role'::text), ''::text), (SESSION_USER)::text) = ANY (ARRAY['service_role'::text, 'postgres'::text, 'supabase_admin'::text])) OR
    COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.read'::text), false)));

CREATE POLICY "organization_settings_update" ON "better_supabase"."organization_settings"
  FOR UPDATE
  TO "authenticated"
  USING
    (((COALESCE(NULLIF((auth.jwt() ->> 'role'::text), ''::text), (SESSION_USER)::text) = ANY (ARRAY['service_role'::text, 'postgres'::text, 'supabase_admin'::text])) OR
    COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false)))
  WITH
    CHECK
    (((COALESCE(NULLIF((auth.jwt() ->> 'role'::text), ''::text), (SESSION_USER)::text) = ANY (ARRAY['service_role'::text, 'postgres'::text, 'supabase_admin'::text])) OR
    COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false)));

CREATE POLICY "user_settings_own" ON "better_supabase"."user_settings"
  FOR ALL
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

COMMENT ON VIEW "better_supabase"."audit_log" IS 'deprecated: use better_supabase.audit_events';

GRANT EXECUTE ON FUNCTION "better_supabase"."api_key_tenant"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit"(regclass, text[], boolean, text[], text, text, text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."audit_append_only"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_events_tenants"(interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_events_tenants"(interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_schema"(text, text, text[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."audit_schema_calls"(text, text, text[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."can"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can"(text, uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_assign"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_assign"(uuid, text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_user"(uuid, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_user"(uuid, text, uuid, text) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."comment_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."comment_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."comments_after_write"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."create_api_key"(text, text, text, uuid, boolean, text[], timestamp WITH time zone, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_api_key"(text, text, text, uuid, boolean, text[], timestamp WITH time zone, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_comment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_comment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."edit_comment"(uuid, text, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."edit_comment"(uuid, text, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_organization_settings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_organization_settings"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_user_settings"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_user_settings"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."has_organization_role"(uuid, text[]) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "better_supabase"."has_scope"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."is_platform"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."is_platform"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_api_keys"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_api_keys"(uuid) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."list_audit_events"(uuid, text, uuid, text, text, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, text, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_audit_events"(uuid, text, uuid, text, text, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, text, integer)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_comments"(uuid, text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."member_organization_ids"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."member_organization_ids"(text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."membership_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."membership_claims"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."organization_member_role"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_member_role"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."purge_audit_log"(interval, integer, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_audit_log"(interval, integer, uuid, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_activity"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_activity"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reset_organization_setting"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reset_organization_setting"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reset_user_setting"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reset_user_setting"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."revoke_api_key"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."revoke_api_key"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rotate_api_key"(uuid, text, text, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rotate_api_key"(uuid, text, text, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_organization_setting"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_organization_setting"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_user_setting"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_user_setting"(text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_disabled"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."tenant_ids_with"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."tenant_ids_with"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unaudit"(regclass) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."user_disabled"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."user_disabled"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."verify_api_key"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."verify_api_key"(text, text) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."activity_entries" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."activity_entries" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."api_keys" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."audit_events" TO "service_role";

GRANT INSERT ("body"), UPDATE ("body") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT UPDATE ("deleted_at") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT INSERT ("mentions"), UPDATE ("mentions") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT INSERT ("organization_id") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT INSERT ("parent_id") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT INSERT ("subject_id") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT INSERT ("subject_type") ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT SELECT ON TABLE "better_supabase"."comments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."comments" TO "service_role";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "better_supabase"."organization_settings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."organization_settings" TO "service_role";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "better_supabase"."user_settings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."user_settings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."audit_log" TO "service_role";

ALTER TABLE "better_supabase"."api_keys"
  ADD CONSTRAINT "api_keys_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX api_keys_created_by_idx ON better_supabase.api_keys USING btree (created_by);

ALTER TABLE "better_supabase"."comments"
  ADD CONSTRAINT "comments_author_id_fkey" FOREIGN KEY (author_id) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX comments_author_idx ON better_supabase.comments USING btree (author_id);

CREATE POLICY "comments_insert" ON "better_supabase"."comments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((author_id = ( SELECT auth.uid() AS uid)) AND COALESCE(better_supabase.can('tenant'::text, organization_id, 'comments.create'::text), false) AND
    better_supabase.comment_subject_readable(subject_type, subject_id, organization_id)));

CREATE POLICY "comments_update" ON "better_supabase"."comments"
  FOR UPDATE
  TO "authenticated"
  USING (((author_id = ( SELECT auth.uid() AS uid)) OR COALESCE(better_supabase.can('tenant'::text, organization_id, 'comments.moderate'::text), false)))
  WITH CHECK (((author_id = ( SELECT auth.uid() AS uid)) OR COALESCE(better_supabase.can('tenant'::text, organization_id, 'comments.moderate'::text), false)));

ALTER TABLE "better_supabase"."organization_settings"
  ADD CONSTRAINT "organization_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX organization_settings_updated_by_idx ON better_supabase.organization_settings USING btree (updated_by);

ALTER TABLE "better_supabase"."user_settings"
  ADD CONSTRAINT "user_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX user_settings_updated_by_idx ON better_supabase.user_settings USING btree (updated_by);
