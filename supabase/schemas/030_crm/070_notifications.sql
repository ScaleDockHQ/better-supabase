-- Per-user notifications behind the unread badge. The table broadcasts a
-- change signal per organization (060_realtime.sql); each client recounts its
-- own unread rows through RLS.
create table public.notifications (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_organization_id_idx on public.notifications (organization_id);
create index notifications_user_id_idx on public.notifications (user_id);
create index notifications_unread_idx on public.notifications (user_id, created_at desc)
  where read_at is null;

alter table public.notifications enable row level security;

create policy notifications_own on public.notifications
  for all to authenticated
  using (
    user_id = (select auth.uid())
    and organization_id = (select better_supabase.current_tenant_id())
  )
  with check (
    user_id = (select auth.uid())
    and organization_id = (select better_supabase.current_tenant_id())
  );
