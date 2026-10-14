create table public.plan_features (
  plan_key text not null references public.plans (key) on delete cascade,
  feature_key text not null,
  included boolean not null default true,
  value jsonb,
  primary key (plan_key, feature_key)
);

alter table public.plan_features enable row level security;

create policy plan_features_read on public.plan_features
  for select to authenticated
  using (true);

revoke all on public.plan_features from anon, authenticated;

grant select on public.plan_features to authenticated;

grant all on public.plan_features to service_role;
