-- A table the app already had before better-supabase.
create table public.notes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id),
  title text not null,
  body text,
  created_at timestamptz not null default now()
);

alter table public.notes enable row level security;

create policy notes_owner on public.notes
  for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
