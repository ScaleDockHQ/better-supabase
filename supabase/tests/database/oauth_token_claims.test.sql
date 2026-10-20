-- A token from an external authorization server reaches Postgres as the claims
-- accessTokenResolver forwards: auth.uid() is the token's sub, RLS filters by
-- it, and client_id and scope stay readable for policies.
begin;
select plan(4);

create table public.oauth_probe (id int primary key, owner uuid not null);
alter table public.oauth_probe enable row level security;
create policy oauth_probe_owner on public.oauth_probe
  for select to authenticated using (owner = (select auth.uid()));
grant select on public.oauth_probe to authenticated;
insert into public.oauth_probe values
  (1, '00000000-0000-4000-8000-0000000000a1'),
  (2, '00000000-0000-4000-8000-0000000000b1');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","client_id":"app_1","scope":"openid rows:read"}',
  true
);
set local role authenticated;

select is(
  (select auth.uid())::text,
  '00000000-0000-4000-8000-0000000000a1',
  'auth.uid() is the token sub'
);
select results_eq(
  $$select id from public.oauth_probe$$,
  $$values (1)$$,
  'RLS returns only the rows of the token subject'
);
select is(
  current_setting('request.jwt.claims', true)::jsonb ->> 'client_id',
  'app_1',
  'the client id is readable from the claims'
);
select ok(
  (current_setting('request.jwt.claims', true)::jsonb ->> 'scope') like '%rows:read%',
  'the scope is readable from the claims'
);

select * from finish();
rollback;
