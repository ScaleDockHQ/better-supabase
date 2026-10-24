-- better-supabase module: realtime-tables
-- @bsb-block-data realtime-tables
-- @bsb-hash sha256:3b77f16dda58cdfbf3bba8ef718621e4a7773c5e943f52e4406ff2c1cbae5f10
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('realtime-tables', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
