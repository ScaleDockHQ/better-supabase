-- The assets module on the fixture's access contract, with PostGIS: the admin
-- (…00a1) of Acme (…0001) builds a location tree and assigns an asset to the
-- member (…00a2), the member reads only what they may, and Globex (…0002)
-- sees nothing.
begin;
select plan(17);

insert into better_supabase.booking_resources (id, tenant_id, name)
values ('00000000-0000-4000-8000-00000000b001', '00000000-0000-4000-8000-000000000001', 'Room 1');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.site', better_supabase.create_asset_location(
  '00000000-0000-4000-8000-000000000001', 'site', 'HQ', code => 'HQ',
  latitude => 52.37, longitude => 4.89,
  area => '{"type":"Polygon","coordinates":[[[4.88,52.36],[4.90,52.36],[4.90,52.38],[4.88,52.38],[4.88,52.36]]]}'
) ->> 'id', true);
select set_config('test.building', better_supabase.create_asset_location(
  '00000000-0000-4000-8000-000000000001', 'building', 'B1',
  parent_id => current_setting('test.site')::uuid
) ->> 'id', true);

select throws_ok(
  $$select better_supabase.create_asset_location('00000000-0000-4000-8000-000000000001', 'site', 'Again', code => 'HQ')$$,
  '23505',
  null,
  'a location code is unique in the organization'
);
select throws_ok(
  format(
    $$select better_supabase.update_asset_location(%L, jsonb_build_object('parentId', %L))$$,
    current_setting('test.site'), current_setting('test.building')
  ),
  '23514',
  null,
  'a location can''t move inside its own sublocation'
);

select set_config('test.asset', better_supabase.create_asset(
  '00000000-0000-4000-8000-000000000001', 'laptop', 'MBP',
  location_id => current_setting('test.building')::uuid, tag => 'IT-1',
  latitude => 52.371, longitude => 4.891
) ->> 'id', true);

select throws_ok(
  $$select better_supabase.create_asset('00000000-0000-4000-8000-000000000001', 'laptop', 'Again', tag => 'IT-1')$$,
  '23505',
  null,
  'an asset tag is unique in the organization'
);
select isnt(
  (select point from better_supabase.assets where id = current_setting('test.asset')::uuid),
  null,
  'the geography point is generated from latitude and longitude'
);
select is(
  jsonb_array_length(better_supabase.get_asset(current_setting('test.asset')::uuid) -> 'locationPath'),
  2,
  'an asset reads its location path from the top'
);
select is(
  jsonb_array_length(better_supabase.list_assets(
    '00000000-0000-4000-8000-000000000001', current_setting('test.site')::uuid, true
  )),
  1,
  'listing a site with its sublocations finds the asset in the building'
);
select is(
  jsonb_array_length(better_supabase.assets_near(
    '00000000-0000-4000-8000-000000000001', 52.37, 4.89, 1000
  ) -> 'assets'),
  1,
  'near finds the asset within the radius'
);
select is(
  jsonb_array_length(better_supabase.assets_near(
    '00000000-0000-4000-8000-000000000001', 52.37, 4.89, 10
  ) -> 'assets'),
  0,
  'near leaves out an asset outside the radius'
);
select is(
  better_supabase.asset_locations_at('00000000-0000-4000-8000-000000000001', 52.37, 4.89) -> 0 ->> 'id',
  current_setting('test.site'),
  'the site''s area contains the point'
);

select is(
  better_supabase.assign_asset(
    current_setting('test.asset')::uuid, 'member', '00000000-0000-4000-8000-0000000000a2'
  ) ->> 'assigneeId',
  '00000000-0000-4000-8000-0000000000a2',
  'the admin assigns the asset to the member'
);
select throws_ok(
  format(
    $$select better_supabase.assign_asset(%L, 'member', '00000000-0000-4000-8000-0000000000a3')$$,
    current_setting('test.asset')
  ),
  '22023',
  null,
  'a member of another organization can''t hold the asset'
);

select better_supabase.set_asset_link(
  'booking_resource', '00000000-0000-4000-8000-00000000b001', current_setting('test.asset')::uuid
);
select is(
  better_supabase.get_asset(current_setting('test.asset')::uuid) -> 'links' -> 'bookingResources' -> 0 ->> 'name',
  'Room 1',
  'a booking resource can name the asset'
);
select throws_ok(
  format($$select better_supabase.archive_asset_location(%L)$$, current_setting('test.site')),
  '55000',
  null,
  'a location with open sublocations can''t be archived'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from better_supabase.assets),
  1,
  'the member reads the organization''s assets'
);
select throws_ok(
  $$select better_supabase.create_asset('00000000-0000-4000-8000-000000000001', 'laptop', 'Mine')$$,
  '42501',
  null,
  'a member can''t create assets'
);
select is(
  (select count(*)::integer from better_supabase.asset_assignments),
  1,
  'the member reads the assignment history of assets they can see'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from better_supabase.assets) + (select count(*)::integer from better_supabase.asset_locations),
  0,
  'Globex sees none of Acme''s locations or assets'
);

select * from finish();
rollback;
