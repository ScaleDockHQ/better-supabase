-- better-supabase module: moderation
-- @bsb-block-data moderation
-- @bsb-hash sha256:76179abfb148c92e0be04adaecaa07a03f622a837c1d9705f26da1f6e15fc254
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.moderation_items', target_type => 'moderation_item', event_prefix => 'moderation_item', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('moderation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
