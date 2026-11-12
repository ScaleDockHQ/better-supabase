create table stripe.subscription_items (
  id text primary key,
  subscription text,
  price text,
  quantity integer,
  created integer
);

alter table stripe.subscription_items enable row level security;

revoke all on stripe.subscription_items from anon, authenticated;

grant all on stripe.subscription_items to service_role;
