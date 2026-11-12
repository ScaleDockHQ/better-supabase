create table stripe.invoices (
  id text primary key,
  customer text,
  number text,
  status text,
  currency text,
  total integer,
  created integer,
  hosted_invoice_url text
);

alter table stripe.invoices enable row level security;

revoke all on stripe.invoices from anon, authenticated;

grant all on stripe.invoices to service_role;
