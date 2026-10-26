create or replace function better_supabase.app_organization_invitations(organization uuid)
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
  select i.id, i.email, coalesce(r.key, i.role), coalesce(p.full_name, p.email), i.created_at, i.expires_at
  from better_supabase.invitations i
  left join better_supabase.roles r on r.id::text = i.role
  left join better_supabase.profiles p on p.id = i.invited_by
  where i.organization_id = organization
    and i.accepted_at is null and i.declined_at is null and i.revoked_at is null
    and i.expires_at >= now()
  order by i.created_at desc;
end;
$$;

revoke execute on function better_supabase.app_organization_invitations(uuid) from public, anon;

grant execute on function better_supabase.app_organization_invitations(uuid) to authenticated, service_role;
