create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  email text,
  created_at timestamptz not null default now()
);

alter table public.contacts enable row level security;

grant select, insert, update on public.contacts to authenticated;
