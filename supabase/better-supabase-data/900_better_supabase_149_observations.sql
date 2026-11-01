-- better-supabase module: observations
-- @bsb-block-data observations
-- @bsb-hash sha256:66751fff920e238e938902e8a21ddd2c486ad2e4e8c05e0f5c833e236bf83f16
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- blocks.observations.options.defaults: the vital signs, as system
-- definitions every organization reads.
insert into "better_supabase"."observation_definitions" ("tenant_id", "key", "title", "value_type", "unit", "code_system", "code", "components", "decimals", "valid_low", "valid_high", "reference_low", "reference_high", "critical_low", "critical_high")
values
  (null, 'heart_rate', 'Heart rate', 'integer', '/min', 'http://loinc.org', '8867-4', null, null, 0, 350, 51, 90, 40, 131),
  (null, 'blood_pressure', 'Blood pressure', 'components', null, 'http://loinc.org', '85354-9', '[{"key":"systolic","title":"Systolic","unit":"mm[Hg]","code":"8480-6","validLow":0,"validHigh":350,"referenceLow":100,"referenceHigh":140,"criticalLow":90,"criticalHigh":220}, {"key":"diastolic","title":"Diastolic","unit":"mm[Hg]","code":"8462-4","validLow":0,"validHigh":250,"referenceLow":60,"referenceHigh":90,"criticalLow":40,"criticalHigh":130}]'::jsonb, null, null, null, null, null, null, null),
  (null, 'body_temperature', 'Body temperature', 'number', 'Cel', 'http://loinc.org', '8310-5', null, 1, 20, 46, 36.1, 38, 35, 39.1),
  (null, 'respiratory_rate', 'Respiratory rate', 'integer', '/min', 'http://loinc.org', '9279-1', null, null, 0, 100, 12, 20, 8, 25),
  (null, 'oxygen_saturation', 'Oxygen saturation', 'integer', '%', 'http://loinc.org', '2708-6', null, null, 0, 100, 96, null, 91, null),
  (null, 'body_weight', 'Body weight', 'number', 'kg', 'http://loinc.org', '29463-7', null, 1, 0, 700, null, null, null, null),
  (null, 'body_height', 'Body height', 'number', 'cm', 'http://loinc.org', '8302-2', null, 1, 0, 300, null, null, null, null),
  (null, 'pain_score', 'Pain score', 'integer', '{score}', 'http://loinc.org', '72514-3', null, null, 0, 10, null, 3, null, null),
  (null, 'blood_glucose', 'Blood glucose', 'number', 'mmol/L', 'http://loinc.org', '15074-8', null, 1, 0, 60, 4, 7.8, 3, 20)
on conflict ("tenant_id", "key") do nothing;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.observations', target_type => 'observation', event_prefix => 'observation', deferred => true);
select better_supabase.audit('better_supabase.observation_definitions', target_type => 'observation_definition', event_prefix => 'observation_definition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('observations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
