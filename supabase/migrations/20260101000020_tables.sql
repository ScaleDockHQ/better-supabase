create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email text not null,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  kvk text,
  status text not null default 'lead' check (status in ('lead', 'active', 'archived')),
  primary_contact_id uuid references public.contacts (id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid,
  updated_by uuid,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint customers_organization_id_kvk_key unique (organization_id, kvk)
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null references public.customers (id) on delete cascade,
  label text not null,
  city text,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  color text not null default 'gray' check (color in ('gray', 'red', 'green', 'blue')),
  constraint tags_organization_id_name_key unique (organization_id, name)
);

create table public.customer_tags (
  customer_id uuid not null references public.customers (id) on delete cascade,
  tag_id uuid not null references public.tags (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  primary key (customer_id, tag_id)
);

create table public.notes (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  customer_id uuid not null references public.customers (id) on delete cascade,
  kind public.note_kind not null default 'call',
  body text not null,
  attachments jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index contacts_organization_id_idx on public.contacts (organization_id);
create index customers_organization_id_idx on public.customers (organization_id);
create index customers_primary_contact_id_idx on public.customers (primary_contact_id);
create index locations_customer_id_idx on public.locations (customer_id);
create index locations_organization_id_idx on public.locations (organization_id);
create index tags_organization_id_idx on public.tags (organization_id);
create index customer_tags_tag_id_idx on public.customer_tags (tag_id);
create index customer_tags_organization_id_idx on public.customer_tags (organization_id);
create index notes_customer_id_idx on public.notes (customer_id);
create index notes_organization_id_idx on public.notes (organization_id);
