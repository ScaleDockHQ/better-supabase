-- Who belongs to which organization, with which role. The app owns this
-- table and the memberships block runs over it (ADR 0098); `role` is a row
-- of the permissions block's catalog (`permissions.model: "catalog"` in
-- apps/examples/nextjs/better-supabase.config.ts).
create table public.memberships (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role uuid not null references better_supabase.roles (id) on delete restrict,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  primary key (organization_id, user_id)
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

grant all on public.memberships to service_role;

revoke all on public.memberships from anon, authenticated;

grant select on public.memberships to authenticated;
