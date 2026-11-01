-- better-supabase module: medications
-- @bsb-block-data medications
-- @bsb-hash sha256:41372d590702f147c30e79d65e1ae554e2807e334a4de76caf7ebd12113351ca
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.medications', target_type => 'medication', event_prefix => 'medication', deferred => true);
select better_supabase.audit('better_supabase.medication_orders', target_type => 'medication_order', event_prefix => 'medication_order', deferred => true);
select better_supabase.audit('better_supabase.medication_administrations', target_type => 'medication_administration', event_prefix => 'medication_administration', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('medications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
