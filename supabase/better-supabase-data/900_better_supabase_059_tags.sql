-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:4a538cb00afa1154676f39e52532164e88416b6ba1d30e3c1dc6425a7b495b0a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.tags', target_type => 'tag', event_prefix => 'tag', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
