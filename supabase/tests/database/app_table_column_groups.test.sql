-- The before update trigger of appTables columnGroups: a signed-in user needs
-- the group's permission in the row's tenant to change its columns, and the
-- service role needs nothing. The table and trigger below are the shape the
-- renderer emits (src/sql/modules/app-table-groups.ts), on a table that exists
-- only inside this test. The group's permission is approvals.manage, which Ann
-- (…a1, owner of Acme …0001) holds and Ben (…a2, a member) does not
-- (supabase/seed.sql).
begin;
select plan(7);

create table public.cg_pgtap (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text,
  budget bigint,
  rate bigint
);
grant select, update on public.cg_pgtap to authenticated, service_role;

create function better_supabase.cg_pgtap_column_groups()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if new."budget" is distinct from old."budget"
      or new."rate" is distinct from old."rate" then
    if not coalesce(better_supabase.can('tenant', old."organization_id", 'approvals.manage'), false) then
      raise exception 'updating the money columns of public.cg_pgtap needs the approvals.manage permission'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger bsb_column_groups before update on public.cg_pgtap
  for each row execute function better_supabase.cg_pgtap_column_groups();

insert into public.cg_pgtap (id, organization_id, name, budget, rate)
values ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-000000000001', 'Plan', 100, 10);

-- Ben, a member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$update public.cg_pgtap set name = 'Plan B'$$,
  'a member changes a column outside the group'
);
select lives_ok(
  $$update public.cg_pgtap set budget = 100$$,
  'a member can write a group column back to its current value'
);
select throws_ok(
  $$update public.cg_pgtap set budget = 500$$,
  '42501',
  'updating the money columns of public.cg_pgtap needs the approvals.manage permission',
  'a member without the permission cannot change a group column'
);
select throws_ok(
  $$update public.cg_pgtap set rate = 99$$,
  '42501',
  null,
  'every column of the group needs the same permission'
);

-- Ann, the owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select lives_ok(
  $$update public.cg_pgtap set budget = 500$$,
  'an owner with the permission changes a group column'
);

-- The service role.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select lives_ok(
  $$update public.cg_pgtap set rate = 20$$,
  'the service role is not checked'
);

reset role;
select is(
  (select rate from public.cg_pgtap),
  20::bigint,
  'the service role change was stored'
);

select * from finish();
rollback;
