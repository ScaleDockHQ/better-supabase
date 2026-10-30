-- ==== schema supabase/schemas/900_better_supabase_038_waitlist.sql
-- better-supabase module: waitlist
-- @bsb-block waitlist@1 managed
-- @bsb-hash sha256:b1346507a1e2d2bc61baf15ba6c0cca1860c8eda715817e32d8c29b006b8e12c
-- A waitlist with positions and approvals, and hashed invite codes with a use limit, an expiry and an optional organization and role. waitlist_admit() backs a before-user-created hook that only lets approved addresses or valid codes sign up.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invite_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invite_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invite_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invite_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invite_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- People waiting for access. join_waitlist() adds them; staff approve or
-- reject; the before-user-created hook lets approved addresses sign up.
create table if not exists "better_supabase"."waitlist_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "email" text not null unique check ("email" = lower("email") and "email" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "status" text not null default 'waiting' check ("status" in ('waiting', 'approved', 'rejected', 'joined')),
  "position" bigint generated always as identity,
  "referrer" text check (length("referrer") <= 200),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object' and pg_column_size("metadata") <= 4096),
  "user_id" uuid references auth.users (id) on delete set null,
  "decided_by" uuid references auth.users (id) on delete set null,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists waitlist_entries_status_idx on "better_supabase"."waitlist_entries" ("status", "position");
create index if not exists waitlist_entries_user_idx on "better_supabase"."waitlist_entries" ("user_id");
create index if not exists waitlist_entries_decided_by_idx on "better_supabase"."waitlist_entries" ("decided_by");
alter table "better_supabase"."waitlist_entries" enable row level security;
revoke all on "better_supabase"."waitlist_entries" from public, anon, authenticated;
grant all on "better_supabase"."waitlist_entries" to service_role;

-- Invite codes, stored as the SHA-256 of the upper-cased code. One with an
-- organization also adds the user to it with role (or defaultRole).
create table if not exists "better_supabase"."invite_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "code_hash" text not null unique,
  "prefix" text not null,
  "max_uses" integer check ("max_uses" > 0),
  "uses" integer not null default 0 check ("uses" >= 0),
  "expires_at" timestamptz,
  "workspace_id" uuid,
  "role" text check ("role" is null or "workspace_id" is not null),
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create index if not exists invite_codes_tenant_idx on "better_supabase"."invite_codes" ("workspace_id");
create index if not exists invite_codes_created_by_idx on "better_supabase"."invite_codes" ("created_by");
alter table "better_supabase"."invite_codes" enable row level security;
revoke all on "better_supabase"."invite_codes" from public, anon, authenticated;
grant all on "better_supabase"."invite_codes" to service_role;

create table if not exists "better_supabase"."invite_code_redemptions" (
  "code_id" uuid not null references "better_supabase"."invite_codes" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "redeemed_at" timestamptz not null default now(),
  primary key ("code_id", "user_id")
);
create index if not exists invite_code_redemptions_user_idx on "better_supabase"."invite_code_redemptions" ("user_id");
alter table "better_supabase"."invite_code_redemptions" enable row level security;
revoke all on "better_supabase"."invite_code_redemptions" from public, anon, authenticated;
grant all on "better_supabase"."invite_code_redemptions" to service_role;

-- { position, status } for an address; adding it again changes nothing.
-- Open to anon, so rate-limit the route that calls it. Only the service role
-- sees an entry's real status: everyone else reads 'waiting', and an entry that
-- left the line gets the place a new address would, so the answer never tells
-- whether someone was approved or signed up. fields: the extra columns
-- (blocks.waitlist.options.extraColumns), written only on a new entry.
drop function if exists "better_supabase"."join_waitlist"(text, text, jsonb, jsonb);
create or replace function "better_supabase"."join_waitlist"(email text, referrer text default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text := lower(trim(join_waitlist.email));
  v_row "better_supabase"."waitlist_entries";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'Not an email address' using errcode = '22023', hint = 'WAITLIST_EMAIL_INVALID';
  end if;
  insert into "better_supabase"."waitlist_entries" as x ("email", "referrer", "metadata")
  values (v_email, join_waitlist.referrer, coalesce(join_waitlist.metadata, '{}'::jsonb))
  on conflict ("email") do update set "email" = x."email"
  returning * into v_row;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return jsonb_build_object(
      'position', case when v_row."status" = 'waiting' then (
        select count(*) from "better_supabase"."waitlist_entries" w where w."status" = 'waiting' and w."position" <= v_row."position"
      ) end,
      'status', case when v_row."status" = 'rejected' then 'waiting' else v_row."status" end
    );
  end if;
  return jsonb_build_object(
    'position', case when v_row."status" = 'waiting' then (
      select count(*) from "better_supabase"."waitlist_entries" w where w."status" = 'waiting' and w."position" <= v_row."position"
    ) else (
      select count(*) + 1 from "better_supabase"."waitlist_entries" w where w."status" = 'waiting'
    ) end,
    'status', 'waiting'
  );
end;
$$;

create or replace function "better_supabase"."list_waitlist"(status text default 'waiting', page_size integer default 50, after_position bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) then
    raise exception 'You may not manage the waitlist' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."position"), '[]'::jsonb)
    from (
      select * from "better_supabase"."waitlist_entries" w
      where (list_waitlist.status is null or w."status" = list_waitlist.status)
        and (list_waitlist.after_position is null or w."position" > list_waitlist.after_position)
      order by w."position"
      limit least(greatest(coalesce(list_waitlist.page_size, 50), 1), 500)
    ) x
  );
end;
$$;

-- Approves or rejects an entry. Approving emits waitlist_entry.approved, for the
-- email that says they can sign up.
create or replace function "better_supabase"."decide_waitlist_entry"(id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."waitlist_entries";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) then
    raise exception 'You may not manage the waitlist' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  update "better_supabase"."waitlist_entries" x set
    "status" = case when decide_waitlist_entry.approve then 'approved' else 'rejected' end,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."id" = decide_waitlist_entry.id and x."status" in ('waiting', 'approved', 'rejected')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No open waitlist entry %', decide_waitlist_entry.id using errcode = 'P0002', hint = 'WAITLIST_NOT_FOUND';
  end if;
  if decide_waitlist_entry.approve then
    null;
  else
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Creates an invite code: platform staff for any, inviters (members.invite)
-- for their organization's. The app generates the code; only its hash is kept.
create or replace function "better_supabase"."create_invite_code"(code text, max_uses integer default 1, expires_at timestamptz default null, tenant uuid default null, role text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invite_codes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) or (create_invite_code.tenant is not null and coalesce(better_supabase.can('tenant', create_invite_code.tenant, 'waitlist.invite'), false))) then
    raise exception 'You may not create this invite code' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  if length(trim(create_invite_code.code)) < 8 then
    raise exception 'Invite codes need at least 8 characters' using errcode = '22023', hint = 'WAITLIST_CODE_INVALID';
  end if;
  if create_invite_code.role is not null and not (create_invite_code.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'An invite code can''t grant role %', create_invite_code.role using errcode = '22023', hint = 'WAITLIST_ROLE_INVALID';
  end if;
  if create_invite_code.role is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false)))
    and not coalesce(better_supabase.can_assign(create_invite_code.tenant, create_invite_code.role), false) then
    raise exception 'You may not grant role %', create_invite_code.role using errcode = '42501', hint = 'WAITLIST_ROLE_FORBIDDEN';
  end if;
  insert into "better_supabase"."invite_codes" ("code_hash", "prefix", "max_uses", "expires_at", "workspace_id", "role")
  values (
    encode(extensions.digest(upper(trim(create_invite_code.code)), 'sha256'), 'hex'),
    upper(left(trim(create_invite_code.code), 4)),
    create_invite_code.max_uses,
    create_invite_code.expires_at,
    create_invite_code.tenant,
    create_invite_code.role
  )
  returning * into v_row;
  null;
  return to_jsonb(v_row) - 'code_hash';
exception when unique_violation then
  raise exception 'That invite code exists' using errcode = '23505', hint = 'WAITLIST_CODE_TAKEN';
end;
$$;

create or replace function "better_supabase"."list_invite_codes"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) or (list_invite_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_invite_codes.tenant, 'waitlist.invite'), false))) then
    raise exception 'You may not see these invite codes' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - 'code_hash' order by x."created_at" desc), '[]'::jsonb)
    from "better_supabase"."invite_codes" x
    where x."workspace_id" is not distinct from list_invite_codes.tenant
  );
end;
$$;

create or replace function "better_supabase"."revoke_invite_code"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_code "better_supabase"."invite_codes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."workspace_id" into v_tenant from "better_supabase"."invite_codes" x where x."id" = revoke_invite_code.id;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'waitlist.invite'), false))) then
    raise exception 'You may not revoke this invite code' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  update "better_supabase"."invite_codes" x set "revoked_at" = now()
  where x."id" = revoke_invite_code.id and x."revoked_at" is null
  returning * into v_code;
  if v_code."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;

-- Whether an address may sign up: approved on the waitlist, or carrying a
-- usable code. For the before-user-created hook; it consumes nothing.
create or replace function "better_supabase"."waitlist_admit"(email text, code text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from "better_supabase"."waitlist_entries" x
    where x."email" = lower(trim(waitlist_admit.email)) and x."status" in ('approved', 'joined')
  ) then
    return jsonb_build_object('allowed', true, 'reason', 'approved');
  end if;
  if waitlist_admit.code is not null and exists (
    select 1 from "better_supabase"."invite_codes" x where x."code_hash" = encode(extensions.digest(upper(trim(waitlist_admit.code)), 'sha256'), 'hex') and x."revoked_at" is null
      and (x."expires_at" is null or x."expires_at" > now())
      and (x."max_uses" is null or x."uses" < x."max_uses")
  ) then
    return jsonb_build_object('allowed', true, 'reason', 'code');
  end if;
  return jsonb_build_object('allowed', false, 'reason', case when waitlist_admit.code is null then 'waiting' else 'code_invalid' end);
end;
$$;

-- Uses one code for member: counts it, and adds them to its organization.
-- { organizationId, role }, role null when they were a member already; or
-- raises WAITLIST_CODE_INVALID.
create or replace function "better_supabase"."redeem_for"(code text, member uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code "better_supabase"."invite_codes";
  v_role text;
  v_added boolean;
begin
  select * into v_code from "better_supabase"."invite_codes" x
  where x."code_hash" = encode(extensions.digest(upper(trim(redeem_for.code)), 'sha256'), 'hex')
  for update;
  if v_code."id" is null or not (v_code."revoked_at" is null
      and (v_code."expires_at" is null or v_code."expires_at" > now())
      and (v_code."max_uses" is null or v_code."uses" < v_code."max_uses")) then
    raise exception 'This invite code is not valid' using errcode = '22023', hint = 'WAITLIST_CODE_INVALID';
  end if;
  insert into "better_supabase"."invite_code_redemptions" ("code_id", "user_id") values (v_code."id", redeem_for.member)
  on conflict do nothing;
  if not found then
    raise exception 'You already used this invite code' using errcode = '23505', hint = 'WAITLIST_CODE_USED';
  end if;
  update "better_supabase"."invite_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  if v_code."workspace_id" is not null then
    v_role := coalesce(v_code."role", 'member');
    insert into "better_supabase"."memberships" ("workspace_id", "user_id", "role")
    values (v_code."workspace_id", redeem_for.member, v_role)
    on conflict do nothing;
    v_added := found;
    if v_added then
      null;
    else
      v_role := null;
    end if;
  end if;
  return jsonb_build_object('organizationId', v_code."workspace_id", 'role', v_role);
end;
$$;

-- For a signed-in user, e.g. a code that joins an organization.
create or replace function "better_supabase"."redeem_invite_code"(code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  return "better_supabase"."redeem_for"(redeem_invite_code.code, auth.uid());
end;
$$;

-- On sign-up: marks the waitlist entry joined and redeems the code the
-- client passed in user metadata (invite_code), then drops it from the metadata.
create or replace function "better_supabase"."waitlist_on_auth_user"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := new.raw_user_meta_data ->> 'invite_code';
begin
  update "better_supabase"."waitlist_entries" x set "status" = 'joined', "user_id" = new.id
  where x."email" = lower(new.email) and x."status" <> 'joined';
  if v_code is not null then
    begin
      perform "better_supabase"."redeem_for"(v_code, new.id);
    exception when others then
      raise warning 'better-supabase: invite code for % not redeemed: %', new.id, sqlerrm;
    end;
    update auth.users u set raw_user_meta_data = u.raw_user_meta_data - 'invite_code' where u.id = new.id;
  end if;
  return null;
exception when others then
  raise warning 'better-supabase: waitlist sign-up for % failed: %', new.id, sqlerrm;
  return null;
end;
$$;
revoke execute on function "better_supabase"."waitlist_on_auth_user"() from public, anon, authenticated;
drop trigger if exists "bsb_waitlist_auth_user" on auth.users;
create trigger "bsb_waitlist_auth_user" after insert on auth.users
  for each row execute function "better_supabase"."waitlist_on_auth_user"();

revoke execute on function "better_supabase"."join_waitlist"(text, text, jsonb) from public;
revoke execute on function "better_supabase"."list_waitlist"(text, integer, bigint) from public, anon;
revoke execute on function "better_supabase"."decide_waitlist_entry"(uuid, boolean) from public, anon;
revoke execute on function "better_supabase"."create_invite_code"(text, integer, timestamptz, uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_invite_codes"(uuid) from public, anon;
revoke execute on function "better_supabase"."revoke_invite_code"(uuid) from public, anon;
revoke execute on function "better_supabase"."waitlist_admit"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."redeem_for"(text, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."redeem_invite_code"(text) from public, anon;
grant execute on function "better_supabase"."join_waitlist"(text, text, jsonb) to anon, authenticated, service_role;
grant execute on function "better_supabase"."list_waitlist"(text, integer, bigint) to authenticated, service_role;
grant execute on function "better_supabase"."decide_waitlist_entry"(uuid, boolean) to authenticated, service_role;
grant execute on function "better_supabase"."create_invite_code"(text, integer, timestamptz, uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_invite_codes"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."revoke_invite_code"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."waitlist_admit"(text, text) to service_role, supabase_auth_admin;
grant execute on function "better_supabase"."redeem_for"(text, uuid) to service_role;
grant execute on function "better_supabase"."redeem_invite_code"(text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_038_waitlist.sql
-- better-supabase module: waitlist
-- @bsb-block-data waitlist
-- @bsb-hash sha256:d2114d835d02603771b06e4c11a5f251e18b9573fe93b85c85fa3c3fa26c3374
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('waitlist', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
