SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.credential_delete (
  provider text,
  name     text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."credential_delete"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.credential_get (
  provider text,
  name     text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."credential_get"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.credential_set (
  provider    text,
  name        text,
  secret      text,
  description text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."credential_set"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.credential_delete (
  provider text,
  name     text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_delete.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_delete.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  delete from vault.secrets s where s.name = 'bs:cred:' || credential_delete.provider || ':' || credential_delete.name;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.credential_get (
  provider text,
  name     text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_get.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_get.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  return (
    select ds.decrypted_secret from vault.decrypted_secrets ds
    where ds.name = 'bs:cred:' || credential_get.provider || ':' || credential_get.name
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.credential_set (
  provider    text,
  name        text,
  secret      text,
  description text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  return v_id;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."credential_delete"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."credential_delete"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."credential_get"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."credential_get"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."credential_set"(text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."credential_set"(text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."credential_delete"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."credential_delete"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."credential_get"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."credential_get"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."credential_set"(text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."credential_set"(text, text, text, text) TO "service_role";
