-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:4bb15b3dc7b3519077541886245e20b0585fcd2a0be14886b47311e20fc85d54
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.expense_reports', target_type => 'expense_report', event_prefix => 'expense_report', deferred => true);
select better_supabase.audit('better_supabase.expense_lines', target_type => 'expense_line', event_prefix => 'expense_line', deferred => true);
select better_supabase.audit('better_supabase.expense_categories', target_type => 'expense_category', event_prefix => 'expense_category', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
