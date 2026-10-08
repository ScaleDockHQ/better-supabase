SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."ai_files"
  DROP CONSTRAINT "ai_files_filename_check";

CREATE TABLE "better_supabase"."push_devices" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"      uuid                     NOT NULL,
  "token"        text                     NOT NULL,
  "platform"     text                     NOT NULL,
  "provider"     text                     NOT NULL DEFAULT 'expo'::text,
  "device_name"  text,
  "app_version"  text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "last_seen_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "push_devices_app_version_check" CHECK ((length(app_version) <= 50)),
  CONSTRAINT "push_devices_device_name_check" CHECK ((length(device_name) <= 200)),
  CONSTRAINT "push_devices_pkey" PRIMARY KEY (id),
  CONSTRAINT "push_devices_platform_check" CHECK ((platform = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text]))),
  CONSTRAINT "push_devices_provider_check" CHECK ((provider = ANY (ARRAY['expo'::text, 'fcm'::text, 'apns'::text, 'webpush'::text]))),
  CONSTRAINT "push_devices_token_check" CHECK (((length(token) >= 1) AND (length(token) <= 4096))),
  CONSTRAINT "push_devices_token_key" UNIQUE (token)
);

ALTER TABLE "better_supabase"."push_devices"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.prune_push_tokens (
  tokens text[]
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."prune_push_tokens"($1) $function$;

CREATE OR REPLACE FUNCTION api.push_tokens_for (
  users uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."push_tokens_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.register_push_device (
  token       text,
  platform    text,
  provider    text DEFAULT 'expo'::text,
  device_name text DEFAULT NULL::text,
  app_version text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."register_push_device"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.unregister_push_device (
  token text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unregister_push_device"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.prune_push_tokens (
  tokens text[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tokens' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if prune_push_tokens.tokens is null or cardinality(prune_push_tokens.tokens) > 1000 then
    raise exception 'pass at most 1000 values' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  delete from "better_supabase"."push_devices" x where x."token" = any (prune_push_tokens.tokens);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.push_tokens_for (
  users uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads push tokens' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if push_tokens_for.users is null or cardinality(push_tokens_for.users) > 1000 then
    raise exception 'pass at most 1000 values' using errcode = '22023', hint = 'PUSH_TOO_MANY';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', x."user_id",
      'token', x."token",
      'platform', x."platform",
      'provider', x."provider"
    ) order by x."user_id", x."last_seen_at" desc), '[]'::jsonb)
    from "better_supabase"."push_devices" x
    where x."user_id" = any (push_tokens_for.users)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_push_device (
  token       text,
  platform    text,
  provider    text DEFAULT 'expo'::text,
  device_name text DEFAULT NULL::text,
  app_version text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_new boolean;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if register_push_device.platform is null or register_push_device.platform not in ('ios', 'android', 'web') then
    raise exception 'Unknown push platform %', register_push_device.platform using errcode = '22023', hint = 'PUSH_PLATFORM';
  end if;
  if register_push_device.provider is null or register_push_device.provider not in ('expo', 'fcm', 'apns', 'webpush') then
    raise exception 'Unknown push provider %', register_push_device.provider using errcode = '22023', hint = 'PUSH_PROVIDER';
  end if;
  if register_push_device.token is null or length(register_push_device.token) not between 1 and 4096 then
    raise exception 'A push token is 1 to 4096 characters' using errcode = '22023', hint = 'PUSH_TOKEN';
  end if;
  insert into "better_supabase"."push_devices" as x ("user_id", "token", "platform", "provider", "device_name", "app_version")
  values (
    v_user,
    register_push_device.token,
    register_push_device.platform,
    register_push_device.provider,
    left(register_push_device.device_name, 200),
    left(register_push_device.app_version, 50)
  )
  on conflict ("token") do update set
    "user_id" = excluded."user_id",
    "platform" = excluded."platform",
    "provider" = excluded."provider",
    "device_name" = coalesce(excluded."device_name", x."device_name"),
    "app_version" = coalesce(excluded."app_version", x."app_version"),
    "last_seen_at" = now()
  returning x."id", (x.xmax = 0) into v_id, v_new;
  if v_new then
    null;
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unregister_push_device (
  token text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  delete from "better_supabase"."push_devices" x
  where x."token" = unregister_push_device.token
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."user_id" = v_user)
  returning x."id", x."user_id" into v_id, v_user;
  if v_id is null then
    return false;
  end if;
  null;
  return true;
end;
$function$;

ALTER TABLE "better_supabase"."ai_files"
  ADD CONSTRAINT "ai_files_filename_check"
    CHECK ((((length(filename) >= 1) AND (length(filename) <= 255)) AND (filename !~ '[/\\]'::text) AND (filename <> ALL (ARRAY['.'::text, '..'::text]))));

ALTER TABLE "better_supabase"."push_devices"
  ADD CONSTRAINT "push_devices_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX push_devices_user_idx ON better_supabase.push_devices USING btree (user_id);

CREATE POLICY "push_devices_own_delete" ON "better_supabase"."push_devices"
  FOR DELETE
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "push_devices_own_read" ON "better_supabase"."push_devices"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

REVOKE ALL ON FUNCTION "api"."prune_push_tokens"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."prune_push_tokens"(text[]) TO "service_role";

REVOKE ALL ON FUNCTION "api"."push_tokens_for"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."push_tokens_for"(uuid[]) TO "service_role";

REVOKE ALL ON FUNCTION "api"."register_push_device"(text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."register_push_device"(text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."unregister_push_device"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unregister_push_device"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."prune_push_tokens"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."prune_push_tokens"(text[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."push_tokens_for"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."push_tokens_for"(uuid[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."register_push_device"(text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."register_push_device"(text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unregister_push_device"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unregister_push_device"(text) TO "authenticated", "service_role";

GRANT DELETE, SELECT ON TABLE "better_supabase"."push_devices" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."push_devices" TO "service_role";
