-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:4cee0a048ddd856428aef75144221ad55d0d384991b77983988f435dd6af2d1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Open items store v4: rows for unallocated payments and future issue dates.
select "better_supabase"."rebuild_open_items_of"(x.tenant) from (
  select "tenant_id" as tenant from "better_supabase"."invoices"
  union
  select "tenant_id" from "better_supabase"."ledger_accounts" where "managed_by" = 'invoices' and "holder_type" = 'invoice_party'
) x;

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
