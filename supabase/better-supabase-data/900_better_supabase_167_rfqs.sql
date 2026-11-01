-- better-supabase module: rfqs
-- @bsb-block-data rfqs
-- @bsb-hash sha256:4f060bda0baa0954c3319bfb338686aa96c7946ee6b9106908b1bba5bf406eaa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('rfqs', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
