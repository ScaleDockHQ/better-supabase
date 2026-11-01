-- better-supabase module: payroll-export
-- @bsb-block-data payroll-export
-- @bsb-hash sha256:c83b874cb875b5f06f0293827e6c7f2aaa9d617bb4088ab8aec60e86d981df85
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.payroll_runs', target_type => 'payroll_run', event_prefix => 'payroll_run', deferred => true);
select better_supabase.audit('better_supabase.payroll_lines', target_type => 'payroll_line', event_prefix => 'payroll_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('payroll-export', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
