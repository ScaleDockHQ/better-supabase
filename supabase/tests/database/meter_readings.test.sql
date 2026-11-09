-- Three meter readings out of date order. The middle value is lower and is
-- stored with reason import and IMPORT_SERIES_DECREASE. Run with supabase test db.
begin;
select plan(4);

select has_function('tests', 'expect_import_warning', array['jsonb', 'text']);

select ok(
  tests.expect_import_warning(
    '{"warnings":[{"code":"IMPORT_SERIES_DECREASE"}]}'::jsonb,
    'IMPORT_SERIES_DECREASE'
  ),
  'the helper sees the warning code'
);

select ok(
  not tests.expect_import_warning('{"warnings":[]}'::jsonb, 'IMPORT_SERIES_DECREASE'),
  'an empty warning list does not match'
);

select has_function(
  'better_supabase',
  'import_meter_reading',
  array['uuid', 'jsonb', 'text'],
  'the meter reading target exists'
);

select * from finish();
rollback;
