create table stripe.customers (
  id text primary key,
  email text,
  name text,
  created integer
);

alter table stripe.customers enable row level security;

revoke all on stripe.customers from anon, authenticated;

grant all on stripe.customers to service_role;
