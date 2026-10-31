-- The dam module against the seed: the Acme owner (…a1) records a rendition
-- on a drive file, grants and revokes usage rights and checks usage. The
-- Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(12);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('dam_renditions', 'dam_usage_rights')
     and rowsecurity),
  2::bigint,
  'the dam tables have RLS enabled'
);
select table_privs_are('better_supabase', 'dam_usage_rights', 'anon', '{}'::text[],
  'anon has no privileges on usage rights');
select table_privs_are('better_supabase', 'dam_renditions', 'anon', '{}'::text[],
  'anon has no privileges on renditions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.file',
  api.drive_create_file('00000000-0000-4000-8000-000000000001', null, 'Logo.png', 'image/png', 10) -> 'node' ->> 'id',
  true
);

select is(
  better_supabase.record_rendition(
    '00000000-0000-4000-8000-000000000001', current_setting('test.file')::uuid, 'thumbnail',
    '{"format": "image/webp", "width": 320, "height": 200}'::jsonb) ->> 'status',
  'ready',
  'a rendition is recorded as ready'
);
select is(
  (better_supabase.record_rendition(
    '00000000-0000-4000-8000-000000000001', current_setting('test.file')::uuid, 'thumbnail',
    '{"status": "failed", "error": "unsupported"}'::jsonb) ->> 'status'),
  'failed',
  'recording the same kind again replaces the row'
);
select is(
  jsonb_array_length(better_supabase.list_renditions('00000000-0000-4000-8000-000000000001', current_setting('test.file')::uuid)),
  1,
  'one row per kind'
);
select throws_ok(
  format($$select better_supabase.record_rendition('00000000-0000-4000-8000-000000000001', %L, 'Bad Kind')$$, current_setting('test.file')),
  '22023',
  null,
  'a kind is lowercase'
);

select set_config(
  'test.right',
  better_supabase.grant_usage_right(
    '00000000-0000-4000-8000-000000000001',
    jsonb_build_object('nodeId', current_setting('test.file'), 'licensee', 'Acme Press', 'territory', 'EU',
      'expiresOn', (current_date + 10)::text)) ->> 'id',
  true
);
select is(
  better_supabase.check_usage(
    '00000000-0000-4000-8000-000000000001', current_setting('test.file')::uuid, '{"territory": "EU"}'::jsonb) ->> 'allowed',
  'true',
  'an active right allows its territory'
);
select is(
  better_supabase.check_usage(
    '00000000-0000-4000-8000-000000000001', current_setting('test.file')::uuid, '{"territory": "US"}'::jsonb) ->> 'allowed',
  'false',
  'another territory is not covered'
);
select throws_ok(
  format($$select better_supabase.grant_usage_right('00000000-0000-4000-8000-000000000001', jsonb_build_object('nodeId', %L, 'licensee', 'Late', 'startsOn', '2030-01-02', 'expiresOn', '2030-01-01'))$$, current_setting('test.file')),
  '22023',
  null,
  'a right cannot end before it starts'
);
select is(
  better_supabase.revoke_usage_right(current_setting('test.right')::uuid) ->> 'status',
  'revoked',
  'a right can be revoked'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.dam_usage_rights),
  0::bigint,
  'another tenant sees no usage rights'
);

select * from finish();
rollback;
