-- The app's own tables. better-supabase adopts them and never rewrites this file.
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  constraint memberships_organization_user_key unique (organization_id, user_id)
);

create index memberships_user_id_idx on public.memberships (user_id);
