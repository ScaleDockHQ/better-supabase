-- better-supabase module: messaging
-- @bsb-block-data messaging
-- @bsb-hash sha256:0c7b44a6331db002bc57c85f33b2758272c55ddd625ceb076b17b027a98b2966
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.messages', target_type => 'message', event_prefix => 'message', deferred => true);
select better_supabase.audit('better_supabase.conversations', target_type => 'conversation', event_prefix => 'conversation', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('messaging', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
