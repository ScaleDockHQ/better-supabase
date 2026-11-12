create table stripe.prices (
  id text primary key,
  product text,
  currency text,
  unit_amount integer,
  created integer
);

alter table stripe.prices enable row level security;

revoke all on stripe.prices from anon, authenticated;

grant all on stripe.prices to service_role;
