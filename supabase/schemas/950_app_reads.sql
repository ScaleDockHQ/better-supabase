-- Reads the Next.js example needs that no SQL module provides: the caller's
-- organizations for the switcher, an organization's members and open
-- invitations for the settings pages, and the caller's own profile. The
-- profiles and invitations tables live in `better_supabase`, which the Data
-- API doesn't expose, and public.organizations shows only the active one.

create or replace function public.my_organizations()
returns table (id uuid, name text, slug text, role text, plan text, last_used_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select o.id, o.name, o.slug, m.role, s.plan_key, m.last_used_at
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  left join public.subscriptions s on s.organization_id = o.id
  where m.user_id = (select auth.uid())
  order by o.name;
end;
$$;

create or replace function public.organization_members(organization uuid)
returns table (user_id uuid, role text, full_name text, email text, avatar_url text, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.read') then
    raise exception 'Not allowed to list members' using errcode = '42501';
  end if;
  return query
  select m.user_id, m.role, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, m.created_at
  from public.memberships m
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by better_supabase.role_rank(m.role) desc, coalesce(p.full_name, u.email::text);
end;
$$;

create or replace function public.organization_invitations(organization uuid)
returns table (id uuid, email text, role text, invited_by text, created_at timestamptz, expires_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.invite') then
    raise exception 'Not allowed to list invitations' using errcode = '42501';
  end if;
  return query
  select i.id, i.email, i.role, coalesce(p.full_name, p.email), i.created_at, i.expires_at
  from better_supabase.invitations i
  left join better_supabase.profiles p on p.id = i.invited_by
  where i.organization_id = organization
    and i.accepted_at is null and i.declined_at is null and i.revoked_at is null
    and i.expires_at >= now()
  order by i.created_at desc;
end;
$$;

create or replace function public.my_profile()
returns table (full_name text, email text, username text, avatar_url text)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return query
  select p.full_name, p.email, p.username, p.avatar_url
  from better_supabase.profiles p
  where p.id = (select auth.uid());
end;
$$;

-- Security invoker: the profiles module's column grants and update policy
-- decide what the caller may change.
create or replace function public.update_my_profile(full_name text)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  update better_supabase.profiles p
  set full_name = nullif(btrim(update_my_profile.full_name), ''), updated_at = now()
  where p.id = (select auth.uid());
end;
$$;

revoke execute on function public.my_organizations() from public, anon;
revoke execute on function public.organization_members(uuid) from public, anon;
revoke execute on function public.organization_invitations(uuid) from public, anon;
revoke execute on function public.my_profile() from public, anon;
revoke execute on function public.update_my_profile(text) from public, anon;
grant execute on function public.my_organizations() to authenticated, service_role;
grant execute on function public.organization_members(uuid) to authenticated, service_role;
grant execute on function public.organization_invitations(uuid) to authenticated, service_role;
grant execute on function public.my_profile() to authenticated, service_role;
grant execute on function public.update_my_profile(text) to authenticated, service_role;
