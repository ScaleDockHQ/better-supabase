-- A B2C app: every row belongs to one user. There are no organizations, so no
-- tenant column, no membership and no tenant policy anywhere.
create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  email text,
  username text,
  full_name text,
  first_name text,
  last_name text,
  avatar_url text,
  display_name text,
  onboarding jsonb not null default '{}',
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.todos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null,
  done boolean not null default false,
  created_at timestamptz not null default now()
);

create index todos_user_id_idx on public.todos (user_id);

alter table public.todos enable row level security;

grant select, insert, update, delete on public.todos to authenticated;
grant all on public.todos to service_role;

create policy todos_owner_select on public.todos
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy todos_owner_insert on public.todos
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy todos_owner_update on public.todos
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy todos_owner_delete on public.todos
  for delete to authenticated
  using (user_id = (select auth.uid()));
