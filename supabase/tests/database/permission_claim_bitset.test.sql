-- The access token hook writes the permission claim as a catalog hash and a
-- bitset, so it stays near 60 bytes however many keys the catalog holds. A
-- catalog that grows keeps the claim small; the app reads it over the
-- generated `permissionKeys` and falls back to `my_permissions()` on a hash it
-- does not know.
begin;
select plan(5);

create function pg_temp.claim()
returns jsonb
language sql
as $$
  select better_supabase.permission_claims_bitset(
    '00000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000002'::uuid
  )
$$;

select is(
  (pg_temp.claim() -> '00000000-0000-4000-8000-000000000002' ->> 'h'),
  (select left(md5(string_agg(key, E'\n' order by key collate "C")), 8) from better_supabase.permissions),
  'the claim carries the hash of the catalog sorted by code point'
);

select cmp_ok(
  octet_length(pg_temp.claim()::text),
  '<=',
  160,
  'the claim stays under 160 bytes'
);

select is(
  length(pg_temp.claim() -> '00000000-0000-4000-8000-000000000002' ->> 'b'),
  (
    select length(rtrim(encode(decode(repeat('00', ceil(count(*) / 8.0)::int), 'hex'), 'base64'), '='))
    from better_supabase.permissions
  ),
  'the bitset has one bit per catalog key'
);

select is(
  better_supabase.permission_claims_bitset(
    '00000000-0000-4000-8000-000000000001'::uuid,
    null
  ),
  '{}'::jsonb,
  'no tenant gives an empty claim'
);

select is(
  better_supabase.permission_bitset(array['a', 'b', 'c'], array['a', 'c']),
  'BQ',
  'bit i of byte i / 8, least significant bit first, base64url without padding'
);

select * from finish();
rollback;
