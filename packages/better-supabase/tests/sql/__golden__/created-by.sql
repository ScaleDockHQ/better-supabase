-- ==== alone: schema supabase/schemas/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block created-by@1 managed
-- @bsb-hash sha256:b08164ab63211cee714b76e82476d403d26ce00a75fc67b95f3658e08cbfb7cb
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := coalesce(auth.uid(), better_supabase.acting_member());
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_actor on %s', target);
  execute format(
    'create trigger bsb_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

-- False for a support or impersonation act, and for an act that only carries
-- session_id, unless act.read_only is false. A token without act may write.

-- using (better_supabase.token_scope_allows('posts:write'))
-- True for a token no OAuth client or agent acts with. A delegated token
-- (a client_id, or an act that is not a support or impersonation level)
-- needs p_scope in its scope claim, a space-separated string or a list.
create or replace function better_supabase.token_scope_allows(p_scope text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    when coalesce(p_scope, '') = '' then false
    when jsonb_typeof(jwt -> 'scope') = 'string'
      then p_scope = any(regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+'))
    when jsonb_typeof(jwt -> 'scope') = 'array'
      then jwt -> 'scope' @> jsonb_build_array(p_scope)
    else false
  end
  from (select auth.jwt() as jwt) as token
$$;
revoke execute on function better_supabase.token_scope_allows(text) from public;
grant execute on function better_supabase.token_scope_allows(text) to anon, authenticated, service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block-data created-by
-- @bsb-hash sha256:60944e1f67ae9e05b433eb2e4935c46e6d61176c538cc3feee165f92923d8911
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('created-by', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block created-by@1 managed
-- @bsb-hash sha256:b08164ab63211cee714b76e82476d403d26ce00a75fc67b95f3658e08cbfb7cb
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := coalesce(auth.uid(), better_supabase.acting_member());
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_actor on %s', target);
  execute format(
    'create trigger bsb_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

-- False for a support or impersonation act, and for an act that only carries
-- session_id, unless act.read_only is false. A token without act may write.

-- using (better_supabase.token_scope_allows('posts:write'))
-- True for a token no OAuth client or agent acts with. A delegated token
-- (a client_id, or an act that is not a support or impersonation level)
-- needs p_scope in its scope claim, a space-separated string or a list.
create or replace function better_supabase.token_scope_allows(p_scope text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    when coalesce(p_scope, '') = '' then false
    when jsonb_typeof(jwt -> 'scope') = 'string'
      then p_scope = any(regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+'))
    when jsonb_typeof(jwt -> 'scope') = 'array'
      then jwt -> 'scope' @> jsonb_build_array(p_scope)
    else false
  end
  from (select auth.jwt() as jwt) as token
$$;
revoke execute on function better_supabase.token_scope_allows(text) from public;
grant execute on function better_supabase.token_scope_allows(text) to anon, authenticated, service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block-data created-by
-- @bsb-hash sha256:60944e1f67ae9e05b433eb2e4935c46e6d61176c538cc3feee165f92923d8911
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('created-by', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block created-by@1 managed
-- @bsb-hash sha256:b08164ab63211cee714b76e82476d403d26ce00a75fc67b95f3658e08cbfb7cb
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := coalesce(auth.uid(), better_supabase.acting_member());
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_actor on %s', target);
  execute format(
    'create trigger bsb_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

-- False for a support or impersonation act, and for an act that only carries
-- session_id, unless act.read_only is false. A token without act may write.

-- using (better_supabase.token_scope_allows('posts:write'))
-- True for a token no OAuth client or agent acts with. A delegated token
-- (a client_id, or an act that is not a support or impersonation level)
-- needs p_scope in its scope claim, a space-separated string or a list.
create or replace function better_supabase.token_scope_allows(p_scope text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    when coalesce(p_scope, '') = '' then false
    when jsonb_typeof(jwt -> 'scope') = 'string'
      then p_scope = any(regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+'))
    when jsonb_typeof(jwt -> 'scope') = 'array'
      then jwt -> 'scope' @> jsonb_build_array(p_scope)
    else false
  end
  from (select auth.jwt() as jwt) as token
$$;
revoke execute on function better_supabase.token_scope_allows(text) from public;
grant execute on function better_supabase.token_scope_allows(text) to anon, authenticated, service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block-data created-by
-- @bsb-hash sha256:60944e1f67ae9e05b433eb2e4935c46e6d61176c538cc3feee165f92923d8911
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('created-by', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block created-by@1 managed
-- @bsb-hash sha256:d3fbda15e12492dfb4b4867360706d7fddd77d44bee0e441cf58c3ba000562f4
-- Sets created_by on insert and updated_by on every write from auth.uid(); an update keeps created_by and the impersonation stamp. Service writes keep the values they send.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.set_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := coalesce(auth.uid(), better_supabase.acting_member());
begin
  if actor is null then
    return new;
  end if;
  if tg_argv[0] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[0],
      case when tg_op = 'INSERT' then to_jsonb(actor) else to_jsonb(old) -> tg_argv[0] end
    ));
  end if;
  if tg_argv[1] = 'updated_by' then
    new.updated_by := actor;
  elsif tg_argv[1] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], actor));
  end if;
  -- The admin behind an impersonated write (the act claim). A user's own
  -- update keeps the stamp, so it cannot clear the record of an earlier one.
  if tg_nargs > 2 and tg_argv[2] <> '' then
    new := jsonb_populate_record(new, jsonb_build_object(
      tg_argv[2],
      case
        when auth.jwt() -> 'act' ->> 'sub' is not null then to_jsonb(auth.jwt() -> 'act' ->> 'sub')
        when tg_op = 'INSERT' then 'null'::jsonb
        else to_jsonb(old) -> tg_argv[2]
      end
    ));
  end if;
  return new;
end;
$$;

-- select better_supabase.track_actor('public.customers');
-- impersonated_by => 'impersonated_by' also stamps the impersonating admin.
create or replace function better_supabase.track_actor(
  target regclass,
  created_by text default 'created_by',
  updated_by text default 'updated_by',
  impersonated_by text default null
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_actor on %s', target);
  execute format(
    'create trigger bsb_actor before insert or update on %s for each row execute function better_supabase.set_actor(%L, %L, %L)',
    target,
    coalesce(created_by, ''),
    coalesce(updated_by, ''),
    coalesce(impersonated_by, '')
  );
end;
$$;

revoke execute on function better_supabase.track_actor(regclass, text, text, text) from public, anon, authenticated;

-- False for a support or impersonation act, and for an act that only carries
-- session_id, unless act.read_only is false. A token without act may write.

-- using (better_supabase.token_scope_allows('posts:write'))
-- True for a token no OAuth client or agent acts with. A delegated token
-- (a client_id, or an act that is not a support or impersonation level)
-- needs p_scope in its scope claim, a space-separated string or a list.
create or replace function better_supabase.token_scope_allows(p_scope text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    when coalesce(p_scope, '') = '' then false
    when jsonb_typeof(jwt -> 'scope') = 'string'
      then p_scope = any(regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+'))
    when jsonb_typeof(jwt -> 'scope') = 'array'
      then jwt -> 'scope' @> jsonb_build_array(p_scope)
    else false
  end
  from (select auth.jwt() as jwt) as token
$$;
revoke execute on function better_supabase.token_scope_allows(text) from public;
grant execute on function better_supabase.token_scope_allows(text) to anon, authenticated, service_role;

-- blocks.created-by.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."token_scope_allows"(p_scope text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."token_scope_allows"($1) $$;
revoke execute on function "api"."token_scope_allows"(text) from public;
grant execute on function "api"."token_scope_allows"(text) to anon, authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_002_created_by.sql
-- better-supabase module: created-by
-- @bsb-block-data created-by
-- @bsb-hash sha256:60944e1f67ae9e05b433eb2e4935c46e6d61176c538cc3feee165f92923d8911
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('created-by', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
