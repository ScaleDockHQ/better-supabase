create table public.notes (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null,
  kind public.note_kind not null default 'call',
  body text not null,
  attachments jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Three dimensions keep the seed readable; real embedding models use hundreds.
  embedding extensions.vector(3),
  constraint notes_customer_id_fkey foreign key (customer_id, organization_id)
    references public.customers (id, organization_id) on delete cascade
);

-- A customer's timeline and the organization feed, newest first.
create index notes_customer_id_idx on public.notes (customer_id, organization_id, created_at desc);
create index notes_organization_id_idx on public.notes (organization_id, created_at desc);
create index notes_embedding_idx on public.notes using hnsw (embedding extensions.vector_cosine_ops);

create trigger notes_set_updated_at before update on public.notes
  for each row execute function better_supabase.set_updated_at();

alter table public.notes enable row level security;

create policy notes_tenant on public.notes
  for all to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()))
  with check (organization_id = (select better_supabase.current_tenant_id()));
