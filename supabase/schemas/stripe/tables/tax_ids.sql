create table stripe.tax_ids (
  id text primary key,
  customer text,
  type text,
  value text,
  created integer
);

alter table stripe.tax_ids enable row level security;

revoke all on stripe.tax_ids from anon, authenticated;

grant all on stripe.tax_ids to service_role;
