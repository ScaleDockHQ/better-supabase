-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:c00c51a11ad9c8aaa07dd314eed28f6c5079977dd7aed37e8fb1a704b4023060
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
