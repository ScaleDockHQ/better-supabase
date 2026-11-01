-- better-supabase module: clinical-decision-support
-- @bsb-block-data clinical-decision-support
-- @bsb-hash sha256:b22e45a5983857209e568a7737b9863b52368538523049650700ee455b27302f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.care_alerts', target_type => 'care_alert', event_prefix => 'care_alert', deferred => true);
select better_supabase.audit('better_supabase.care_rules', target_type => 'care_rule', event_prefix => 'care_rule', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('clinical-decision-support', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
