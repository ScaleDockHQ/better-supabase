-- Who belongs to which organization, with which role. The tenant module runs
-- in custom mode (apps/examples/nextjs/better-supabase.config.ts), so the
-- fixture owns this table; the organizations and invitations modules write
-- to it, and 045_access_contract.sql reads it.

create table public.memberships (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  primary key (organization_id, user_id),
  constraint memberships_role_check check (role in ('owner', 'admin', 'member'))
);

create index memberships_user_idx on public.memberships (user_id);

alter table public.memberships enable row level security;

create policy memberships_read on public.memberships
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or organization_id in (select better_supabase.member_organization_ids())
  );

-- Members change only through the organizations and invitations functions
-- (security definer), never by writing rows.
create policy memberships_no_client_insert on public.memberships
  for insert to authenticated
  with check (false);

create policy memberships_no_client_update on public.memberships
  for update to authenticated
  using (false);

create policy memberships_no_client_delete on public.memberships
  for delete to authenticated
  using (false);

-- Removing a membership clears the tenant claim that points at it, so the
-- next token carries no tenant (the managed tenant module does the same).
create or replace function better_supabase.clear_tenant_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update auth.users u
  set raw_app_meta_data = u.raw_app_meta_data - 'tenant_id'
  where u.id = old.user_id
    and u.raw_app_meta_data ->> 'tenant_id' = old.organization_id::text;
  return null;
end;
$$;

create trigger memberships_clear_tenant_claim after delete on public.memberships
  for each row execute function better_supabase.clear_tenant_claim();
