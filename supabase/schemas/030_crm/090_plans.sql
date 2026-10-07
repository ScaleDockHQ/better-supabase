-- The plan catalog the entitlements module reads (`entitlements.source.plans`
-- in apps/examples/nextjs/better-supabase.config.ts): each organization has
-- one subscription to a plan, and each plan lists its features. Usage quotas
-- match the same plan keys. Stripe Checkout, when configured, updates the
-- subscription row; without Stripe the seeded rows stand.

create table public.plans (
  key text primary key,
  name text not null,
  price_cents integer not null default 0,
  position integer not null default 0
);

create table public.plan_features (
  plan_key text not null references public.plans (key) on delete cascade,
  feature_key text not null,
  included boolean not null default true,
  value jsonb,
  primary key (plan_key, feature_key)
);

create table public.subscriptions (
  organization_id uuid primary key references public.organizations (id) on delete cascade,
  plan_key text not null references public.plans (key),
  status text not null default 'active',
  current_period_end timestamptz,
  updated_at timestamptz not null default now(),
  constraint subscriptions_status_check check (status in ('active', 'trialing', 'past_due', 'canceled'))
);

create index subscriptions_plan_key_idx on public.subscriptions (plan_key);

create trigger subscriptions_set_updated_at before update on public.subscriptions
  for each row execute function better_supabase.set_updated_at();

alter table public.plans enable row level security;
alter table public.plan_features enable row level security;
alter table public.subscriptions enable row level security;

create policy plans_read on public.plans
  for select to authenticated
  using (true);

create policy plan_features_read on public.plan_features
  for select to authenticated
  using (true);

create policy subscriptions_member_read on public.subscriptions
  for select to authenticated
  using (organization_id = (select better_supabase.current_tenant_id()));

-- The billing side (service_role) writes subscriptions; members never do.
create policy subscriptions_no_client_insert on public.subscriptions
  for insert to authenticated
  with check (false);

create policy subscriptions_no_client_update on public.subscriptions
  for update to authenticated
  using (false);

create policy subscriptions_no_client_delete on public.subscriptions
  for delete to authenticated
  using (false);
