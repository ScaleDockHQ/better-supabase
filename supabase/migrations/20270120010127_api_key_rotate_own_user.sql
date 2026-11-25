SET local check_function_bodies = off;

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
  -- The new secret acts as the key's user, so only that user rotates a personal key.
  if old."user_id" is not null and old."user_id" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only its own user can rotate a personal key; revoke it instead' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
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
