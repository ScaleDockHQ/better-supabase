create table stripe.subscriptions (
  id text primary key,
  customer text,
  status text,
  created integer,
  current_period_end integer,
  cancel_at_period_end boolean
);

alter table stripe.subscriptions enable row level security;

revoke all on stripe.subscriptions from anon, authenticated;

grant all on stripe.subscriptions to service_role;
