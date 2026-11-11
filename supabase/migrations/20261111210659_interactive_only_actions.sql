SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.interactive_only (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."interactive_only"($1) $function$;

CREATE OR REPLACE FUNCTION api.interactive_only_role (
  role text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."interactive_only_role"($1) $function$;

CREATE OR REPLACE FUNCTION api.interactive_session()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."interactive_session"() $function$;

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
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role' or ((better_supabase.interactive_session() or not better_supabase.interactive_only_role(can_assign.role)) and better_supabase.can_assign_as(auth.uid(), can_assign.tenant, can_assign.role))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cap_allows (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when jwt is null then true
    when better_supabase.interactive_only(cap_allows.permission)
      and not better_supabase.interactive_session() then false
    when jsonb_typeof(cap) = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(cap) c(key)
        where better_supabase.permission_matches(c.key, cap_allows.permission)
      ) then false
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    else exists (
      select 1
      from unnest(case jsonb_typeof(jwt -> 'scope')
          when 'string' then regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+')
          when 'array' then array(select jsonb_array_elements_text(jwt -> 'scope'))
          else '{}'::text[]
        end) s(scope)
      cross join lateral unnest(better_supabase.scope_permissions(s.scope)) k(key)
      where s.scope <> ''
        and better_supabase.permission_matches(k.key, cap_allows.permission)
    )
  end
  from (select auth.jwt() as jwt) as token
  cross join lateral (
    select coalesce(jwt -> 'bsb_permission_cap', jwt -> 'bs_permission_cap') as cap
  ) as capped
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
  prefix      text                     DEFAULT 'bs'::text,
  kind        text                     DEFAULT NULL::text
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if personal and tenant is null and exists (
      select 1 from better_supabase.member_organization_ids() as m(id)
      where m.id not in (select better_supabase.tenant_ids_with('api_keys.own'))
    ) then
      raise exception 'Not allowed to create API keys for every tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
  end if;
  if exists (select 1 from unnest(coalesce(scopes, '{}')) s where s = any ('{organization.delete,organization.transfer_ownership,platform.invite,sso.manage}'::text[])) then
    raise exception 'Only a signed-in user may use this permission, so an API key cannot carry it' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
  end if;
  if (auth.jwt() -> 'api_key' is not null
      or coalesce(auth.jwt() ->> 'client_id', '') <> ''
      or auth.jwt() -> 'act' is not null) and exists (
    select 1 from unnest(coalesce(scopes, '{}')) s
    where not case
      when auth.jwt() -> 'api_key' is not null then
        coalesce(auth.jwt() -> 'api_key' -> 'scopes', '[]'::jsonb) ?| array['*', s]
      else exists (
        select 1
        from unnest(case jsonb_typeof(auth.jwt() -> 'scope')
            when 'string' then regexp_split_to_array(btrim(auth.jwt() ->> 'scope'), '\s+')
            when 'array' then array(select jsonb_array_elements_text(auth.jwt() -> 'scope'))
            else '{}'::text[]
          end) t(scope)
        where t.scope <> ''
          and (t.scope = s or exists (
            select 1 from unnest(better_supabase.scope_permissions(t.scope)) k(key)
            where better_supabase.permission_matches(k.key, s)
          ))
      )
    end
  ) then
    raise exception 'A token may only give a key the scopes it holds itself' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
  end if;
  if expires_at is not null and expires_at <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  insert into "better_supabase"."api_keys" ("tenant_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "kind", "rate_limit", "expires_at")
  values (tenant, owner, create_api_key.name, create_api_key.prefix, create_api_key.public_id, create_api_key.secret_hash, coalesce(create_api_key.scopes, '{}'), create_api_key.kind, create_api_key.rate_limit, create_api_key.expires_at)
  returning * into created;
  perform "better_supabase".emit_event('api_key.created', jsonb_build_object('keyId', created."id", 'organizationId', created."tenant_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id"), 'api-keys/' || created."id"::text, (created."tenant_id")::text, null, 'better-supabase/api-keys');
  perform better_supabase.audit_event(
    event_type => 'api_key.created',
    category => 'security',
    target_type => 'api_key',
    record_id => created."id"::text,
    target_label => created."name",
    tenant => (created."tenant_id")::uuid,
    metadata => jsonb_build_object('keyId', created."id", 'organizationId', created."tenant_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id")
  );
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."tenant_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'kind', created."kind",
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.interactive_only (
  permission text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(permission = any (array['organization.delete', 'organization.transfer_ownership', 'platform.invite', 'sso.manage']::text[]), false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.interactive_only_role (
  role text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(role = 'owner', false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.interactive_session()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select auth.jwt() is null
    or (auth.jwt() -> 'api_key' is null
      and coalesce(auth.jwt() ->> 'client_id', '') = ''
      and auth.jwt() -> 'act' is null)
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into old from "better_supabase"."api_keys" k where k."id" = rotate_api_key.key for update;
  if old."id" is null or not ((old."tenant_id" is not null and coalesce(better_supabase.can('tenant', old."tenant_id", 'api_keys.manage'), false)) or coalesce(old."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  if (auth.jwt() -> 'api_key' is not null
      or coalesce(auth.jwt() ->> 'client_id', '') <> ''
      or auth.jwt() -> 'act' is not null) and exists (
    select 1 from unnest(coalesce(old."scopes", '{}')) s
    where not case
      when auth.jwt() -> 'api_key' is not null then
        coalesce(auth.jwt() -> 'api_key' -> 'scopes', '[]'::jsonb) ?| array['*', s]
      else exists (
        select 1
        from unnest(case jsonb_typeof(auth.jwt() -> 'scope')
            when 'string' then regexp_split_to_array(btrim(auth.jwt() ->> 'scope'), '\s+')
            when 'array' then array(select jsonb_array_elements_text(auth.jwt() -> 'scope'))
            else '{}'::text[]
          end) t(scope)
        where t.scope <> ''
          and (t.scope = s or exists (
            select 1 from unnest(better_supabase.scope_permissions(t.scope)) k(key)
            where better_supabase.permission_matches(k.key, s)
          ))
      )
    end
  ) then
    raise exception 'A token may only give a key the scopes it holds itself' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
  end if;
  if old."revoked_at" is not null and old."revoked_at" <= now() then
    raise exception 'A revoked API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_REVOKED';
  end if;
  if old."expires_at" is not null and old."expires_at" <= now() then
    raise exception 'An expired API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  if grace is null or grace < interval '0' then
    raise exception 'grace must be zero or more' using errcode = '22023', hint = 'API_KEY_GRACE';
  end if;
  insert into "better_supabase"."api_keys" ("tenant_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "kind", "rate_limit", "expires_at", "rotated_from")
  values (old."tenant_id", old."user_id", old."name", old."prefix", rotate_api_key.public_id, rotate_api_key.secret_hash, old."scopes", old."kind", old."rate_limit", old."expires_at", old."id")
  returning * into created;
  update "better_supabase"."api_keys" k set "revoked_at" = now() + grace where k."id" = old."id";
  perform "better_supabase".emit_event('api_key.rotated', jsonb_build_object('keyId', created."id", 'organizationId', created."tenant_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id", 'previousKeyId', old."id"), 'api-keys/' || created."id"::text, (created."tenant_id")::text, null, 'better-supabase/api-keys');
  perform better_supabase.audit_event(
    event_type => 'api_key.rotated',
    category => 'security',
    target_type => 'api_key',
    record_id => created."id"::text,
    target_label => created."name",
    tenant => (created."tenant_id")::uuid,
    metadata => jsonb_build_object('keyId', created."id", 'organizationId', created."tenant_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id", 'previousKeyId', old."id")
  );
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."tenant_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'kind', created."kind",
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."interactive_only"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."interactive_only"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."interactive_only_role"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."interactive_only_role"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."interactive_session"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."interactive_session"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."interactive_only"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."interactive_only"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."interactive_only_role"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."interactive_only_role"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."interactive_session"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."interactive_session"() TO "anon", "authenticated", "service_role";
