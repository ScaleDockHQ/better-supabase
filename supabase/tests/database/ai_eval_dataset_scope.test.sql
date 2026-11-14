-- ai-evals: get_eval_dataset returns the dataset with its tenant, so a
-- service-role caller can compare it with the caller's organization, and
-- stays closed to every other role.
begin;
select plan(5);

insert into better_supabase.eval_datasets (id, tenant_id, name) values
  ('00000000-0000-4000-8000-00000000e001', '00000000-0000-4000-8000-000000000001', 'acme-set'),
  ('00000000-0000-4000-8000-00000000e002', '00000000-0000-4000-8000-000000000002', 'globex-set'),
  ('00000000-0000-4000-8000-00000000e003', null, 'system-set');

set local role service_role;

select is(
  (select api.get_eval_dataset('00000000-0000-4000-8000-00000000e001') ->> 'tenant_id'),
  '00000000-0000-4000-8000-000000000001',
  'returns the tenant of an Acme dataset'
);

select is(
  (select api.get_eval_dataset('00000000-0000-4000-8000-00000000e002') ->> 'tenant_id'),
  '00000000-0000-4000-8000-000000000002',
  'returns the tenant of a Globex dataset'
);

select is(
  (select api.get_eval_dataset('00000000-0000-4000-8000-00000000e003') ->> 'name'),
  'system-set',
  'returns a system dataset with no tenant'
);

select is(
  api.get_eval_dataset('00000000-0000-4000-8000-00000000e0ff'),
  null,
  'returns null for an unknown id'
);

reset role;
set local role authenticated;

select throws_ok(
  $$select api.get_eval_dataset('00000000-0000-4000-8000-00000000e001')$$,
  '42501',
  null,
  'a signed-in user cannot call it'
);

select * from finish();
rollback;
