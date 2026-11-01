-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:e93aba4eb51441ffda738822604d46c3140f5a7ceff1b471e867cd3e2706bbb5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.post_boards', target_type => 'post_board', event_prefix => 'post_board', deferred => true);
select better_supabase.audit('better_supabase.posts', target_type => 'post', event_prefix => 'post', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
