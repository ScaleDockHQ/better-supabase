create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  number text not null default '',
  status public.invoice_status not null default 'draft',
  currency text not null default 'EUR',
  issued_on date,
  due_on date,
  note text,
  created_at timestamptz not null default now()
);

alter table public.invoices enable row level security;

create policy "members read invoices" on public.invoices
  for select to authenticated
  using (true);

grant select on public.invoices to authenticated;
