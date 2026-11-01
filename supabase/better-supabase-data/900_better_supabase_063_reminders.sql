-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:9a018c1f68e5f775dd43dad880f158928c22cf2839fb5f278b4cdc28a2414185
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.reminders', target_type => 'reminder', event_prefix => 'reminder', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
