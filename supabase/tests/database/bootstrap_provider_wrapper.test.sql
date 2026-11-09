-- The sessions bootstrap wrapper with an authorization provider that sets
-- `subject`, `subjectForTenant` and `bootstrapPermissions` (ADR 0520, 0524).
-- The wrapper below is the exact output of
-- `moduleBody("sessions", ...)`; packages/better-supabase/tests/sql/modules/
-- sessions-pgtap-drift.test.ts fails when the generator's text differs.
begin;
select plan(8);

create schema stubauthz;
create schema stubapp;

create function stubapp.page_data(args jsonb) returns jsonb
language sql stable as $$ select jsonb_build_object('ok', true) $$;

-- The user belongs to tenant ...01 only; ...02 is unknown to them.
create function stubauthz.subject_for_caller() returns jsonb
language sql stable as $$ select jsonb_build_object('tenants', jsonb_build_array('t1', 't2')) $$;

create function stubauthz.subject_for(p_user uuid, p_tenant text) returns jsonb
language sql stable as $$
  select case when p_tenant = 't1'
    then jsonb_build_object('tenants', jsonb_build_array('t1')) end
$$;

create function stubauthz.bootstrap_permissions(p_tenant text) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'apiVersion', 1,
    'tenants', case
      when p_tenant is null then jsonb_build_object('t1', jsonb_build_array('a.read'), 't2', jsonb_build_array('b.read'))
      when p_tenant = 't1' then jsonb_build_object('t1', jsonb_build_array('a.read'))
      else '{}'::jsonb end)
$$;

grant usage on schema stubauthz, stubapp to authenticated;
grant execute on all functions in schema stubauthz, stubapp to authenticated;

create or replace function better_supabase.bootstrap_wrapper(args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select better_supabase.session_active()) then
    return jsonb_build_object(
      'session_active', false,
      'end_reason', better_supabase.session_end_reason(),
      'authz_version', auth.jwt() -> 'authz_ver',
      'token_authz_version', auth.jwt() -> 'authz_ver',
      'tenant', args ->> 'tenant',
      'data', null
    );
  end if;
  return jsonb_build_object(
    'session_active', true,
    'authz_version', auth.jwt() -> 'authz_ver',
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(stubapp.page_data(args)),
    'subject', case when nullif(args ->> 'tenant', '') is null then to_jsonb(stubauthz.subject_for_caller()) else to_jsonb(stubauthz.subject_for(auth.uid(), (args ->> 'tenant'))) end,
    'permissions', to_jsonb(stubauthz.bootstrap_permissions(nullif(args ->> 'tenant', '')))
  );
end;
$$;

revoke execute on function better_supabase.bootstrap_wrapper(jsonb) from public, anon;
grant execute on function better_supabase.bootstrap_wrapper(jsonb) to authenticated;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","aud":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.bootstrap_wrapper('{}') -> 'subject' -> 'tenants',
  '["t1","t2"]'::jsonb,
  'a call without a tenant gets the whole subject'
);

select is(
  better_supabase.bootstrap_wrapper('{"tenant":""}') -> 'subject' -> 'tenants',
  '["t1","t2"]'::jsonb,
  'an empty tenant counts as none'
);

select is(
  better_supabase.bootstrap_wrapper('{"tenant":"t1"}') -> 'subject' -> 'tenants',
  '["t1"]'::jsonb,
  'a named tenant gets the subject restricted to it'
);

select is(
  better_supabase.bootstrap_wrapper('{"tenant":"t9"}') -> 'subject',
  'null'::jsonb,
  'an unknown tenant gets a null subject (fail closed)'
);

select is(
  better_supabase.bootstrap_wrapper('{}') -> 'permissions' -> 'tenants' -> 't2',
  '["b.read"]'::jsonb,
  'permissions for every tenant without a tenant'
);

select is(
  better_supabase.bootstrap_wrapper('{"tenant":"t1"}') -> 'permissions' -> 'tenants',
  '{"t1":["a.read"]}'::jsonb,
  'permissions for the named tenant only'
);

select is(
  better_supabase.bootstrap_wrapper('{"tenant":"t9"}') -> 'permissions' -> 'tenants',
  '{}'::jsonb,
  'an unknown tenant gets no permissions'
);

select is(
  better_supabase.bootstrap_wrapper('{}') -> 'permissions' -> 'apiVersion',
  '1'::jsonb,
  'the permissions carry apiVersion 1'
);

select * from finish();
rollback;
