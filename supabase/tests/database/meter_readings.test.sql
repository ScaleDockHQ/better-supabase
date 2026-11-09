-- The meter reading import target exists and the series trigger guards decreasing readings.
-- Run with supabase test db.
begin;
select plan(2);

select has_function(
  'better_supabase',
  'import_meter_reading',
  array['uuid', 'jsonb', 'text'],
  'the meter reading target exists'
);

select has_trigger(
  'better_supabase',
  'asset_meter_readings',
  'bsb_asset_meter_readings_series',
  'a trigger checks the reading series'
);

select * from finish();
rollback;
