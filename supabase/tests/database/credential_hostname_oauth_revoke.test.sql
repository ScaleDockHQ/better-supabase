-- Revoke semantics for the three configuration kinds that get no archive
-- (ADRs 1041 and 1052): deleting a credential, removing a hostname and deleting
-- an OAuth client each stop it working at once. Run with `supabase test db`.
begin;
select plan(8);

-- A credential: readable until it is deleted, then it is gone from the Vault.
select better_supabase.credential_set('revoke-test', 'api-key', 'secret-1');
select is(better_supabase.credential_get('revoke-test', 'api-key'), 'secret-1', 'a stored credential reads back');
select is(better_supabase.credential_delete('revoke-test', 'api-key'), true, 'deleting a credential succeeds');
select is(better_supabase.credential_get('revoke-test', 'api-key'), null, 'a deleted credential no longer reads');

-- A hostname: resolves once verified, stops resolving once removed.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.host', better_supabase.add_hostname(
  '00000000-0000-4000-8000-000000000001', 'revoke-test.example.com') ->> 'id', true);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.verify_hostname(current_setting('test.host')::uuid);
select is(
  better_supabase.resolve_hostname('revoke-test.example.com') ->> 'organizationId',
  '00000000-0000-4000-8000-000000000001',
  'a verified hostname resolves to its organization'
);
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select is(better_supabase.remove_hostname(current_setting('test.host')::uuid), true, 'removing a hostname succeeds');
select is(
  better_supabase.resolve_hostname('revoke-test.example.com'), null,
  'a removed hostname stops resolving'
);
reset role;

-- An OAuth client: everything it was granted goes with it, because every table
-- that holds a grant references the client with on delete cascade.
select is(
  (select count(*)::integer from pg_constraint c
    where c.contype = 'f' and c.confrelid = 'auth.oauth_clients'::regclass
      and c.conrelid in ('auth.oauth_authorizations'::regclass, 'auth.oauth_consents'::regclass)
      and c.confdeltype <> 'c'),
  0,
  'authorizations and consents of an OAuth client cascade with it'
);
select cmp_ok(
  (select count(*)::integer from pg_constraint c
    where c.contype = 'f' and c.confrelid = 'auth.oauth_clients'::regclass),
  '>=', 2,
  'the grant tables reference the OAuth client'
);

select * from finish();
rollback;
