-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:37751e76a56127dce1317f0c78477e81a04fdbe666b931bb31963b30dc43d93b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ai_scheduled_tasks', target_type => 'ai_scheduled_task', event_prefix => 'ai_scheduled_task', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
