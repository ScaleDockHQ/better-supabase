create function public.customers_owner_team_check()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from better_supabase.teams t
    where t.id = new.owner_team_id
      and t.tenant_id = new.organization_id
  ) then
    raise exception 'owner team belongs to another organization'
      using errcode = '23503', hint = 'CUSTOMER_OWNER_TEAM';
  end if;

  return new;
end;
$$;

revoke execute on function public.customers_owner_team_check() from public, anon, authenticated;

comment on function public.customers_owner_team_check() is 'Keeps customers.owner_team_id inside the customer''s organization.';
