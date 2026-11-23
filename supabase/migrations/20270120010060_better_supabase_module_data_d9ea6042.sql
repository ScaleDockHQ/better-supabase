-- better-supabase add --adopt: the rows and settings of invoices that no data migration holds yet.

set lock_timeout = '5s';

-- invoices
select "better_supabase"."rebuild_open_items_of"(x.tenant) from (
  select "tenant_id" as tenant from "better_supabase"."invoices"
  union
  select "tenant_id" from "better_supabase"."ledger_accounts" where "managed_by" = 'invoices' and "holder_type" = 'invoice_party'
) x;

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
