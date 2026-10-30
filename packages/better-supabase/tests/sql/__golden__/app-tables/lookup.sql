-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- @bsb-hash sha256:f5b621b2485a163d4eaf009953c28fb20f9c6826e2551f2973c847f3d1168c2d
-- The tables the app owns, from `appTables`, in public.
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;

create or replace function "public"."bsb_valid_bsn"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$$;
revoke execute on function "public"."bsb_valid_bsn"(text) from public, anon;
grant execute on function "public"."bsb_valid_bsn"(text) to authenticated, service_role;
create or replace function "public"."bsb_valid_iban"(value text)
returns boolean
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$$;
revoke execute on function "public"."bsb_valid_iban"(text) from public, anon;
grant execute on function "public"."bsb_valid_iban"(text) to authenticated, service_role;

create table if not exists "public"."patients" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "better_supabase"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."keys" (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."patients" add column if not exists "bsn" text;
alter table "public"."patients" add column if not exists "email" text;
alter table "public"."patients" add column if not exists "iban" text;
alter table "public"."patients" add column if not exists "phone" text;
alter table "public"."patients" add column if not exists "born_on" text;
alter table "public"."patients" add column if not exists "bsn_lookup" bytea;
alter table "public"."patients" add column if not exists "email_lookup" bytea;
alter table "public"."patients" add column if not exists "born_on_lookup" bytea;

alter table "public"."keys" add column if not exists "token" text;
alter table "public"."keys" add column if not exists "token_lookup" bytea;

alter table "public"."patients" enable row level security;
revoke all on "public"."patients" from public, anon, authenticated;
grant select ("id", "organization_id", "created_at", "updated_at", "iban", "phone") on "public"."patients" to authenticated;
grant insert ("id", "organization_id", "created_at", "updated_at", "bsn", "email", "iban", "phone", "born_on"), update ("id", "organization_id", "created_at", "updated_at", "bsn", "email", "iban", "phone", "born_on") on "public"."patients" to authenticated;
grant delete on "public"."patients" to authenticated;
grant all on "public"."patients" to service_role;
drop policy if exists patients_select on "public"."patients";
create policy patients_select on "public"."patients"
  for select to authenticated
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists patients_insert on "public"."patients";
create policy patients_insert on "public"."patients"
  for insert to authenticated
  with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists patients_update on "public"."patients";
create policy patients_update on "public"."patients"
  for update to authenticated
  using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()))
  with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists patients_delete on "public"."patients";
create policy patients_delete on "public"."patients"
  for delete to authenticated
  using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_tenant_scope on "public"."patients";
drop policy if exists bsb_tenant_scope_select on "public"."patients";
create policy bsb_tenant_scope_select on "public"."patients" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "public"."patients";
create policy bsb_tenant_scope_insert on "public"."patients" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "public"."patients";
create policy bsb_tenant_scope_update on "public"."patients" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "public"."patients";
create policy bsb_tenant_scope_delete on "public"."patients" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
alter table "public"."patients" drop constraint if exists "patients_iban_check";
alter table "public"."patients" add constraint "patients_iban_check" check ("public"."bsb_valid_iban"("iban"));
alter table "public"."patients" drop constraint if exists "patients_phone_check";
alter table "public"."patients" add constraint "patients_phone_check" check ("phone" ~* '^\+[1-9][0-9]{1,14}$');
create index if not exists "patients_organization_id_idx" on "public"."patients" ("organization_id");
create index if not exists "patients_bsn_lookup_idx" on "public"."patients" ("bsn_lookup");
create index if not exists "patients_email_lookup_idx" on "public"."patients" ("email_lookup");
create index if not exists "patients_born_on_lookup_idx" on "public"."patients" ("born_on_lookup");
drop trigger if exists "bsb_updated_at" on "public"."patients";
create trigger "bsb_updated_at" before update on "public"."patients"
  for each row execute function better_supabase.set_updated_at();
-- Encrypts bsn, email, born_on with the row's data key before the row is written.
create or replace function "better_supabase"."patients_seal"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text := 'tenant:' || (new."organization_id")::text;
  v_old_owner text;
  v_moved boolean := false;
  v_key text;
  v_lookup_key text;
  v_plain text;
begin
  if tg_op = 'UPDATE' then
    v_old_owner := 'tenant:' || (old."organization_id")::text;
    v_moved := v_owner is distinct from v_old_owner;
  end if;
  if new."bsn" is not null and left(new."bsn", 5) is distinct from 'bsf1:' then
    if not ("public"."bsb_valid_bsn"(new."bsn")) then
      raise exception 'new row for relation "%" violates check constraint "%"', 'patients', 'patients_bsn_check'
        using errcode = '23514';
    end if;
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."bsn_lookup" := "better_supabase"."field_hash"(v_lookup_key, new."bsn");
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."bsn" := "better_supabase"."field_seal"(v_key, new."bsn");
  elsif new."bsn" is not null and v_moved and not case when tg_op = 'INSERT' then true else new."bsn" is distinct from old."bsn" end then
    v_plain := "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."bsn");
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."bsn_lookup" := "better_supabase"."field_hash"(v_lookup_key, v_plain);
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."bsn" := "better_supabase"."field_seal"(v_key, v_plain);
  elsif new."bsn" is null then
    new."bsn_lookup" := null;
  elsif new."bsn_lookup" is null or (tg_op = 'UPDATE' and (new."bsn_lookup" is distinct from old."bsn_lookup" or new."bsn" is distinct from old."bsn")) then
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."bsn_lookup" := "better_supabase"."field_hash"(v_lookup_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_owner, false), new."bsn"));
  end if;
  if new."email" is not null and left(new."email", 5) is distinct from 'bsf1:' then
    if not (new."email" ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
      raise exception 'new row for relation "%" violates check constraint "%"', 'patients', 'patients_email_check'
        using errcode = '23514';
    end if;
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."email_lookup" := "better_supabase"."field_hash"(v_lookup_key, new."email");
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."email" := "better_supabase"."field_seal"(v_key, new."email");
  elsif new."email" is not null and v_moved and not case when tg_op = 'INSERT' then true else new."email" is distinct from old."email" end then
    v_plain := "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."email");
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."email_lookup" := "better_supabase"."field_hash"(v_lookup_key, v_plain);
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."email" := "better_supabase"."field_seal"(v_key, v_plain);
  elsif new."email" is null then
    new."email_lookup" := null;
  elsif new."email_lookup" is null or (tg_op = 'UPDATE' and (new."email_lookup" is distinct from old."email_lookup" or new."email" is distinct from old."email")) then
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."email_lookup" := "better_supabase"."field_hash"(v_lookup_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_owner, false), new."email"));
  end if;
  if new."born_on" is not null and left(new."born_on", 5) is distinct from 'bsf1:' then
    new."born_on" := ((new."born_on")::date)::text;
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."born_on_lookup" := "better_supabase"."field_hash"(v_lookup_key, new."born_on");
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."born_on" := "better_supabase"."field_seal"(v_key, new."born_on");
  elsif new."born_on" is not null and v_moved and not case when tg_op = 'INSERT' then true else new."born_on" is distinct from old."born_on" end then
    v_plain := "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."born_on");
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."born_on_lookup" := "better_supabase"."field_hash"(v_lookup_key, v_plain);
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."born_on" := "better_supabase"."field_seal"(v_key, v_plain);
  elsif new."born_on" is null then
    new."born_on_lookup" := null;
  elsif new."born_on_lookup" is null or (tg_op = 'UPDATE' and (new."born_on_lookup" is distinct from old."born_on_lookup" or new."born_on" is distinct from old."born_on")) then
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."born_on_lookup" := "better_supabase"."field_hash"(v_lookup_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_owner, false), new."born_on"));
  end if;
  return new;
end;
$$;
revoke all on function "better_supabase"."patients_seal"() from public, anon, authenticated;
drop trigger if exists "bsb_seal_fields" on "public"."patients";
create trigger "bsb_seal_fields" before insert or update of "organization_id", "bsn", "email", "born_on", "bsn_lookup", "email_lookup", "born_on_lookup" on "public"."patients"
  for each row execute function "better_supabase"."patients_seal"();
-- Decrypts bsn, email, born_on for the rows the caller reaches, as the table's policies do.
create or replace function "better_supabase"."patients_reveal"(ids uuid[])
returns table (id uuid, "bsn" text, "email" text, "born_on" date)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role reveal patients' using errcode = '42501', hint = 'APP_REVEAL_FORBIDDEN';
  end if;
  if coalesce(cardinality(patients_reveal.ids), 0) > 500 then
    raise exception 'reveal at most 500 rows of patients per call' using errcode = '22023', hint = 'APP_REVEAL_TOO_MANY';
  end if;
  return query
    with r as materialized (
      select t.id, 'tenant:' || (t."organization_id")::text as bsb_owner, t."bsn", t."email", t."born_on"
      from "public"."patients" t
      where t.id = any (patients_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids())))
    ),
    k as materialized (
      select o.bsb_owner, "better_supabase"."field_key"(o.bsb_owner, false) as bsb_key
      from (select distinct r.bsb_owner from r) o
    )
    select r.id, ("better_supabase"."field_open"(k.bsb_key, r."bsn"))::text, ("better_supabase"."field_open"(k.bsb_key, r."email"))::text, ("better_supabase"."field_open"(k.bsb_key, r."born_on"))::date
    from r join k on k.bsb_owner = r.bsb_owner;
end;
$$;
revoke execute on function "better_supabase"."patients_reveal"(uuid[]) from public, anon;
grant execute on function "better_supabase"."patients_reveal"(uuid[]) to authenticated, service_role;
-- The API entry point for "better_supabase"."patients_reveal"; the definer function stays out of the exposed schemas.
create or replace function "public"."patients_reveal"(ids uuid[])
returns table (id uuid, "bsn" text, "email" text, "born_on" date)
language sql
security invoker
set search_path = ''
as $$
  select * from "better_supabase"."patients_reveal"(ids);
$$;
revoke execute on function "public"."patients_reveal"(uuid[]) from public, anon;
grant execute on function "public"."patients_reveal"(uuid[]) to authenticated, service_role;
-- Finds the rows whose bsn, email, born_on equal a value, by their lookup hash, as the table's policies allow.
create or replace function "better_supabase"."patients_find"(lookup_column text, value text)
returns table (id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role find patients' using errcode = '42501', hint = 'APP_FIND_FORBIDDEN';
  end if;
  if patients_find.value is null then
    return;
  end if;
  if patients_find.lookup_column = 'bsn' then
    return query
      with k as materialized (
        select w.bsb_owner, "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(w.bsb_owner, false), patients_find.value) as bsb_hash
        from (select distinct 'tenant:' || (o.id)::text as bsb_owner
        from (
          select t."organization_id" as id from "public"."patients" t where v_service
          union all
          select m.id from better_supabase.member_organization_ids() as m(id) where not v_service
        ) o
        where o.id is not null) w
      )
      select t.id
      from "public"."patients" t
      join k on k.bsb_hash = t."bsn_lookup" and k.bsb_owner = 'tenant:' || (t."organization_id")::text
      where v_service or ("organization_id" in (select better_supabase.member_organization_ids()));
  elsif patients_find.lookup_column = 'email' then
    return query
      with k as materialized (
        select w.bsb_owner, "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(w.bsb_owner, false), patients_find.value) as bsb_hash
        from (select distinct 'tenant:' || (o.id)::text as bsb_owner
        from (
          select t."organization_id" as id from "public"."patients" t where v_service
          union all
          select m.id from better_supabase.member_organization_ids() as m(id) where not v_service
        ) o
        where o.id is not null) w
      )
      select t.id
      from "public"."patients" t
      join k on k.bsb_hash = t."email_lookup" and k.bsb_owner = 'tenant:' || (t."organization_id")::text
      where v_service or ("organization_id" in (select better_supabase.member_organization_ids()));
  elsif patients_find.lookup_column = 'born_on' then
    return query
      with k as materialized (
        select w.bsb_owner, "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(w.bsb_owner, false), ((patients_find.value)::date)::text) as bsb_hash
        from (select distinct 'tenant:' || (o.id)::text as bsb_owner
        from (
          select t."organization_id" as id from "public"."patients" t where v_service
          union all
          select m.id from better_supabase.member_organization_ids() as m(id) where not v_service
        ) o
        where o.id is not null) w
      )
      select t.id
      from "public"."patients" t
      join k on k.bsb_hash = t."born_on_lookup" and k.bsb_owner = 'tenant:' || (t."organization_id")::text
      where v_service or ("organization_id" in (select better_supabase.member_organization_ids()));
  else
    raise exception 'patients keeps a lookup for bsn, email, born_on only' using errcode = '22023', hint = 'APP_FIND_COLUMN';
  end if;
end;
$$;
revoke execute on function "better_supabase"."patients_find"(text, text) from public, anon;
grant execute on function "better_supabase"."patients_find"(text, text) to authenticated, service_role;
-- The API entry point for "better_supabase"."patients_find"; the definer function stays out of the exposed schemas.
create or replace function "public"."patients_find"(lookup_column text, value text)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from "better_supabase"."patients_find"(lookup_column, value);
$$;
revoke execute on function "public"."patients_find"(text, text) from public, anon;
grant execute on function "public"."patients_find"(text, text) to authenticated, service_role;

alter table "public"."keys" enable row level security;
revoke all on "public"."keys" from public, anon, authenticated;
grant select ("id", "created_at", "updated_at") on "public"."keys" to authenticated;
grant all on "public"."keys" to service_role;
drop policy if exists keys_select on "public"."keys";
create policy keys_select on "public"."keys"
  for select to authenticated
  using (((select auth.uid()) is not null and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') <> 'true'));
create index if not exists "keys_token_lookup_idx" on "public"."keys" ("token_lookup");
drop trigger if exists "bsb_updated_at" on "public"."keys";
create trigger "bsb_updated_at" before update on "public"."keys"
  for each row execute function better_supabase.set_updated_at();
-- Encrypts token with the row's data key before the row is written.
create or replace function "better_supabase"."keys_seal"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text := 'app';
  v_old_owner text;
  v_moved boolean := false;
  v_key text;
  v_lookup_key text;
  v_plain text;
begin
  if tg_op = 'UPDATE' then
    v_old_owner := 'app';
    v_moved := v_owner is distinct from v_old_owner;
  end if;
  if new."token" is not null and left(new."token", 5) is distinct from 'bsf1:' then
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."token_lookup" := "better_supabase"."field_hash"(v_lookup_key, new."token");
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."token" := "better_supabase"."field_seal"(v_key, new."token");
  elsif new."token" is not null and v_moved and not case when tg_op = 'INSERT' then true else new."token" is distinct from old."token" end then
    v_plain := "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."token");
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."token_lookup" := "better_supabase"."field_hash"(v_lookup_key, v_plain);
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."token" := "better_supabase"."field_seal"(v_key, v_plain);
  elsif new."token" is null then
    new."token_lookup" := null;
  elsif new."token_lookup" is null or (tg_op = 'UPDATE' and (new."token_lookup" is distinct from old."token_lookup" or new."token" is distinct from old."token")) then
    v_lookup_key := coalesce(v_lookup_key, "better_supabase"."field_lookup_key"(v_owner, true));
    new."token_lookup" := "better_supabase"."field_hash"(v_lookup_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_owner, false), new."token"));
  end if;
  return new;
end;
$$;
revoke all on function "better_supabase"."keys_seal"() from public, anon, authenticated;
drop trigger if exists "bsb_seal_fields" on "public"."keys";
create trigger "bsb_seal_fields" before insert or update of "token", "token_lookup" on "public"."keys"
  for each row execute function "better_supabase"."keys_seal"();
-- Decrypts token for the rows the caller reaches, as the table's policies do.
create or replace function "better_supabase"."keys_reveal"(ids uuid[])
returns table (id uuid, "token" text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role reveal keys' using errcode = '42501', hint = 'APP_REVEAL_FORBIDDEN';
  end if;
  if coalesce(cardinality(keys_reveal.ids), 0) > 500 then
    raise exception 'reveal at most 500 rows of keys per call' using errcode = '22023', hint = 'APP_REVEAL_TOO_MANY';
  end if;
  return query
    with r as materialized (
      select t.id, 'app' as bsb_owner, t."token"
      from "public"."keys" t
      where t.id = any (keys_reveal.ids) and (v_service or (((select auth.uid()) is not null and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') <> 'true')))
    ),
    k as materialized (
      select o.bsb_owner, "better_supabase"."field_key"(o.bsb_owner, false) as bsb_key
      from (select distinct r.bsb_owner from r) o
    )
    select r.id, ("better_supabase"."field_open"(k.bsb_key, r."token"))::text
    from r join k on k.bsb_owner = r.bsb_owner;
end;
$$;
revoke execute on function "better_supabase"."keys_reveal"(uuid[]) from public, anon;
grant execute on function "better_supabase"."keys_reveal"(uuid[]) to authenticated, service_role;
-- The API entry point for "better_supabase"."keys_reveal"; the definer function stays out of the exposed schemas.
create or replace function "public"."keys_reveal"(ids uuid[])
returns table (id uuid, "token" text)
language sql
security invoker
set search_path = ''
as $$
  select * from "better_supabase"."keys_reveal"(ids);
$$;
revoke execute on function "public"."keys_reveal"(uuid[]) from public, anon;
grant execute on function "public"."keys_reveal"(uuid[]) to authenticated, service_role;
-- Finds the rows whose token equal a value, by their lookup hash, as the table's policies allow.
create or replace function "better_supabase"."keys_find"(lookup_column text, value text)
returns table (id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role find keys' using errcode = '42501', hint = 'APP_FIND_FORBIDDEN';
  end if;
  if keys_find.value is null then
    return;
  end if;
  if keys_find.lookup_column = 'token' then
    return query
      with k as materialized (
        select w.bsb_owner, "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(w.bsb_owner, false), keys_find.value) as bsb_hash
        from (select 'app' as bsb_owner) w
      )
      select t.id
      from "public"."keys" t
      join k on k.bsb_hash = t."token_lookup" and k.bsb_owner = 'app'
      where v_service or (((select auth.uid()) is not null and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') <> 'true'));
  else
    raise exception 'keys keeps a lookup for token only' using errcode = '22023', hint = 'APP_FIND_COLUMN';
  end if;
end;
$$;
revoke execute on function "better_supabase"."keys_find"(text, text) from public, anon;
grant execute on function "better_supabase"."keys_find"(text, text) to authenticated, service_role;
-- The API entry point for "better_supabase"."keys_find"; the definer function stays out of the exposed schemas.
create or replace function "public"."keys_find"(lookup_column text, value text)
returns table (id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from "better_supabase"."keys_find"(lookup_column, value);
$$;
revoke execute on function "public"."keys_find"(text, text) from public, anon;
grant execute on function "public"."keys_find"(text, text) to authenticated, service_role;

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- @bsb-hash sha256:2c3346f5d5bac77ec88d161d532ccd1849e53e53b25448e569fa28d36396ea72
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(44);

select extensions.has_table('public', 'patients', 'public.patients exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."patients"'::regclass), 'public.patients has row level security on');
select extensions.policies_are('public', 'patients', array['patients_select', 'patients_insert', 'patients_update', 'patients_delete', 'bsb_tenant_scope_select', 'bsb_tenant_scope_insert', 'bsb_tenant_scope_update', 'bsb_tenant_scope_delete'], 'public.patients has the policies for its scope');
select extensions.col_has_check('public'::name, 'patients'::name, 'iban'::name, 'public.patients.iban has its check');
select extensions.col_has_check('public'::name, 'patients'::name, 'phone'::name, 'public.patients.phone has its check');
select extensions.table_privs_are('public', 'patients', 'anon', array[]::text[], 'anon has no privileges on public.patients');
select extensions.table_privs_are('public', 'patients', 'authenticated', array['DELETE'], 'authenticated has the privileges for its scope on public.patients');
select extensions.ok(not has_column_privilege('authenticated', '"public"."patients"', 'bsn', 'SELECT'), 'authenticated may not select public.patients.bsn');
select extensions.ok(has_column_privilege('authenticated', '"public"."patients"', 'bsn', 'INSERT'), 'authenticated may insert public.patients.bsn');
select extensions.ok(has_column_privilege('authenticated', '"public"."patients"', 'bsn', 'UPDATE'), 'authenticated may update public.patients.bsn');
select extensions.ok(not has_column_privilege('authenticated', '"public"."patients"', 'email', 'SELECT'), 'authenticated may not select public.patients.email');
select extensions.ok(has_column_privilege('authenticated', '"public"."patients"', 'email', 'INSERT'), 'authenticated may insert public.patients.email');
select extensions.ok(has_column_privilege('authenticated', '"public"."patients"', 'email', 'UPDATE'), 'authenticated may update public.patients.email');
select extensions.ok(not has_column_privilege('authenticated', '"public"."patients"', 'born_on', 'SELECT'), 'authenticated may not select public.patients.born_on');
select extensions.ok(has_column_privilege('authenticated', '"public"."patients"', 'born_on', 'INSERT'), 'authenticated may insert public.patients.born_on');
select extensions.ok(has_column_privilege('authenticated', '"public"."patients"', 'born_on', 'UPDATE'), 'authenticated may update public.patients.born_on');
select extensions.has_trigger('public'::name, 'patients'::name, 'bsb_seal_fields'::name, 'public.patients encrypts its encrypted columns');
select extensions.has_function('public'::name, 'patients_reveal'::name, array['uuid[]']::name[], 'public.patients has a reveal function');
select extensions.ok(not has_function_privilege('anon', '"public"."patients_reveal"(uuid[])', 'execute'), 'anon cannot reveal public.patients');

with o as (
  insert into "better_supabase"."organizations" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."patients" ("organization_id") select o.id from o;
update "public"."patients" set "bsn" = ('111222333')::text, "email" = ('test@example.com')::text, "born_on" = ('2026-01-01'::date)::text;
select set_config('bsb.app_reveal_ids', (select array_agg(id)::text from "public"."patients"), true);
select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
select extensions.ok((select bool_and(left("bsn", 5) = 'bsf1:' and "bsn" <> ('111222333')::text) from "public"."patients"), 'public.patients.bsn is ciphertext at rest');
select extensions.is((select r."bsn"::text from "public"."patients_reveal"(current_setting('bsb.app_reveal_ids')::uuid[]) r limit 1), ('111222333')::text, 'the service role reveals public.patients.bsn');
select extensions.ok((select bool_and(left("email", 5) = 'bsf1:' and "email" <> ('test@example.com')::text) from "public"."patients"), 'public.patients.email is ciphertext at rest');
select extensions.is((select r."email"::text from "public"."patients_reveal"(current_setting('bsb.app_reveal_ids')::uuid[]) r limit 1), ('test@example.com')::text, 'the service role reveals public.patients.email');
select extensions.ok((select bool_and(left("born_on", 5) = 'bsf1:' and "born_on" <> ('2026-01-01'::date)::text) from "public"."patients"), 'public.patients.born_on is ciphertext at rest');
select extensions.is((select r."born_on"::text from "public"."patients_reveal"(current_setting('bsb.app_reveal_ids')::uuid[]) r limit 1), ('2026-01-01'::date)::text, 'the service role reveals public.patients.born_on');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."patients"
  for all to authenticated
  using (true)
  with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."patients"), 0, 'a signed-in user does not read a row of public.patients outside their scope even through an app policy using (true)');
select extensions.throws_ok($$insert into "public"."patients" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.patients outside their scope even through an app policy using (true)');
select extensions.is((select count(*)::integer from "public"."patients_reveal"(current_setting('bsb.app_reveal_ids')::uuid[])), 0, 'a signed-in user does not reveal a row of public.patients outside their scope');
select extensions.throws_ok($$select "bsn" from "public"."patients"$$, '42501', null, 'a signed-in user cannot read public.patients.bsn');
select extensions.throws_ok($$select "email" from "public"."patients"$$, '42501', null, 'a signed-in user cannot read public.patients.email');
select extensions.throws_ok($$select "born_on" from "public"."patients"$$, '42501', null, 'a signed-in user cannot read public.patients.born_on');
reset role;

select extensions.has_table('public', 'keys', 'public.keys exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."keys"'::regclass), 'public.keys has row level security on');
select extensions.policies_are('public', 'keys', array['keys_select'], 'public.keys has the policies for its scope');
select extensions.table_privs_are('public', 'keys', 'anon', array[]::text[], 'anon has no privileges on public.keys');
select extensions.table_privs_are('public', 'keys', 'authenticated', array[]::text[], 'authenticated has the privileges for its scope on public.keys');
select extensions.ok(not has_column_privilege('authenticated', '"public"."keys"', 'token', 'SELECT'), 'authenticated may not select public.keys.token');
select extensions.ok(not has_column_privilege('authenticated', '"public"."keys"', 'token', 'INSERT'), 'authenticated may not insert public.keys.token');
select extensions.ok(not has_column_privilege('authenticated', '"public"."keys"', 'token', 'UPDATE'), 'authenticated may not update public.keys.token');
select extensions.has_trigger('public'::name, 'keys'::name, 'bsb_seal_fields'::name, 'public.keys encrypts its encrypted columns');
select extensions.has_function('public'::name, 'keys_reveal'::name, array['uuid[]']::name[], 'public.keys has a reveal function');
select extensions.ok(not has_function_privilege('anon', '"public"."keys_reveal"(uuid[])', 'execute'), 'anon cannot reveal public.keys');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.throws_ok($$insert into "public"."keys" default values$$, '42501', null, 'a signed-in user cannot write public.keys; only the service role does');
select extensions.throws_ok($$select "token" from "public"."keys"$$, '42501', null, 'a signed-in user cannot read public.keys.token');
reset role;

select * from extensions.finish();
rollback;
