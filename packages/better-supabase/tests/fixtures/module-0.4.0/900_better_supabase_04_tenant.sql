-- better-supabase module: tenant
-- Memberships with roles, member_org_ids() and has_org_role() for RLS policies, and membership_claims() for the access token hook. A template: edit the roles to fit your app.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

create table if not exists better_supabase.memberships (
  org_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);
create index if not exists memberships_user_idx on better_supabase.memberships (user_id);

alter table better_supabase.memberships enable row level security;
grant select on better_supabase.memberships to authenticated;
grant all on better_supabase.memberships to service_role;

-- The tenant of the current request: the top-level `tenant_id` claim
-- (custom access token hook) or `app_metadata.tenant_id` (Auth admin API).
-- Never user_metadata: users can write it.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '')::uuid
$$;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_org_ids('{owner,admin}')))
-- has_org_role(org) answers for one organization, in functions and checks.
create or replace function better_supabase.member_org_ids(roles text[] default null)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.org_id
  from better_supabase.memberships m
  where m.user_id = (select auth.uid())
    and (roles is null or m.role = any (roles))
$$;

create or replace function better_supabase.has_org_role(org uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from better_supabase.memberships m
    where m.org_id = org
      and m.user_id = auth.uid()
      and (roles is null or m.role = any (roles))
  )
$$;

drop policy if exists bs_memberships_read on better_supabase.memberships;
create policy bs_memberships_read on better_supabase.memberships
  for select to authenticated
  using (user_id = (select auth.uid()) or org_id in (select better_supabase.member_org_ids()));

revoke execute on function better_supabase.member_org_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_org_role(uuid, text[]) from public, anon;
grant execute on function better_supabase.member_org_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_org_role(uuid, text[]) to authenticated, service_role;

-- The memberships claim: [{ scope, id, roles }]. When an authorization
-- provider writes the hook, it fills the claim instead. Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m.org_id,
      'roles', jsonb_build_array(m.role)
    ) order by m.created_at, m.org_id), '[]'::jsonb)
  from better_supabase.memberships m
  where m.user_id = membership_claims.user_id
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
