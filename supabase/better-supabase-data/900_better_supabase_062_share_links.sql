-- better-supabase module: share-links
-- @bsb-block-data share-links
-- @bsb-hash sha256:a8d7ab710f684c66f6de4c2d5cb0e4cda58005bfcfdc8cf8772fe4e81ef83180
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.share_links', target_type => 'share_link', event_prefix => 'share_link', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('share-links', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
