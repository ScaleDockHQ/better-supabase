-- better-supabase module: bookings
-- @bsb-block-data bookings
-- @bsb-hash sha256:0be24b86857b4b3165acfc8d27e3ffaa1c7b5d0b543aabc07711c4b24a581415
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.bookings', target_type => 'booking', event_prefix => 'booking', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('bookings', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
