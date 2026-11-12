create table stripe.payment_methods (
  id text primary key,
  customer text,
  type text,
  created integer
);

alter table stripe.payment_methods enable row level security;

revoke all on stripe.payment_methods from anon, authenticated;

grant all on stripe.payment_methods to service_role;
