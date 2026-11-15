-- Archive, restore and purge for maintenance plans (ADR 1043). An archived
-- plan leaves the list, is never due and opens no work order; restore brings
-- it back; `purge_maintenance_plan` replaces `delete_maintenance_plan`. Run with
-- `supabase test db`.
begin;
select plan(11);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

insert into better_supabase.maintenance_plans (id, tenant_id, title, kind, every_days, next_due_at)
values ('00000000-0000-4000-8000-00000000e001', '00000000-0000-4000-8000-000000000001',
        'Grease the press', 'time', 30, now() - interval '1 day');

select is(
  (better_supabase.get_maintenance_plan('00000000-0000-4000-8000-00000000e001') ->> 'due')::boolean,
  true,
  'an active plan past its date is due'
);

select isnt(
  better_supabase.archive_maintenance_plan('00000000-0000-4000-8000-00000000e001') ->> 'archivedAt',
  null,
  'archive sets archivedAt'
);
select is(pg_temp.n('maintenance_plan.archived'), 1, 'archive records maintenance_plan.archived once');
select is(
  (better_supabase.get_maintenance_plan('00000000-0000-4000-8000-00000000e001') ->> 'due')::boolean,
  false,
  'an archived plan is never due'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001', '{}'))
    where value ->> 'id' = '00000000-0000-4000-8000-00000000e001'),
  0,
  'the list hides an archived plan'
);
select is(
  jsonb_array_length(better_supabase.list_maintenance_plans('00000000-0000-4000-8000-000000000001', '{"archived": true}')),
  1,
  'the archived filter lists it'
);

select better_supabase.archive_maintenance_plan('00000000-0000-4000-8000-00000000e001');
select is(pg_temp.n('maintenance_plan.archived'), 1, 'archiving twice records nothing more');

select is(
  better_supabase.restore_maintenance_plan('00000000-0000-4000-8000-00000000e001') ->> 'archivedAt',
  null,
  'restore clears archivedAt'
);
select is(pg_temp.n('maintenance_plan.restored'), 1, 'restore records maintenance_plan.restored once');

select is(
  better_supabase.purge_maintenance_plan('00000000-0000-4000-8000-00000000e001') ->> 'id',
  '00000000-0000-4000-8000-00000000e001',
  'purge removes the plan'
);
select hasnt_function(
  'better_supabase',
  'delete_maintenance_plan',
  array['uuid'],
  'delete_maintenance_plan is gone'
);

select * from finish();
rollback;
