-- The plan catalog the entitlements module reads (`entitlements.source.plans`
-- in apps/examples/nextjs/better-supabase.config.ts): each organization has
-- one subscription to a plan, and each plan lists its features. Usage quotas
-- match the same plan keys. Stripe Checkout, when configured, updates the
-- subscription row; without Stripe the seeded rows stand.
create table public.plans (
  key text primary key,
  name text not null,
  price_cents bigint not null default 0,
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  position integer not null default 0
);

alter table public.plans enable row level security;

create policy plans_read on public.plans
  for select to authenticated
  using (true);

revoke all on public.plans from anon, authenticated;

grant select on public.plans to authenticated;

grant all on public.plans to service_role;
