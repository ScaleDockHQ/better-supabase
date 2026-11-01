-- better-supabase module: employees
-- @bsb-block-data employees
-- @bsb-hash sha256:a2103a2f544c56153b3bea07cbbe2a0a422c610c3c939ee72de05ec2d22aca91
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.employees', target_type => 'employee', event_prefix => 'employee', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('employees', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
