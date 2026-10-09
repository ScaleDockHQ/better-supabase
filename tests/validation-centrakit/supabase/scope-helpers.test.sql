-- The policy shapes CentraKit uses with its authorization provider's helpers, against stand-ins:
-- a contact reads quotes through `customer_id in (select customer_ids_with(...))`,
-- an employee through `organization_id in (select organization_ids_with(...))`.
-- Everything lives in a schema this transaction creates and rolls back.
begin;
select plan(9);

create schema scopes_probe;
grant usage on schema scopes_probe to authenticated;

-- Stand-in for the provider's memberships: which permission a user holds where.
create table scopes_probe.scope_grants (
  user_id uuid not null,
  scope text not null check (scope in ('customer', 'organization')),
  scope_id text not null,
  permission text not null
);

create table scopes_probe.quotes (
  id bigint primary key,
  organization_id uuid not null,
  customer_id bigint not null
);
create table scopes_probe.invoices (
  id bigint primary key,
  organization_id uuid not null,
  customer_id bigint not null
);

create function scopes_probe.customer_ids_with(p_permission text)
returns setof bigint
language sql stable security definer set search_path = ''
as $$
  select g.scope_id::bigint from scopes_probe.scope_grants g
  where g.user_id = auth.uid() and g.scope = 'customer' and g.permission = p_permission
$$;

create function scopes_probe.organization_ids_with(p_permission text)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select g.scope_id::uuid from scopes_probe.scope_grants g
  where g.user_id = auth.uid() and g.scope = 'organization' and g.permission = p_permission
$$;

alter table scopes_probe.quotes enable row level security;
alter table scopes_probe.invoices enable row level security;
create policy quotes_read on scopes_probe.quotes for select to authenticated using (
  customer_id in (select scopes_probe.customer_ids_with('quotes.view'))
  or organization_id in (select scopes_probe.organization_ids_with('quotes.view'))
);
create policy invoices_read on scopes_probe.invoices for select to authenticated using (
  customer_id in (select scopes_probe.customer_ids_with('invoices.view'))
  or organization_id in (select scopes_probe.organization_ids_with('invoices.view'))
);
grant select on scopes_probe.quotes, scopes_probe.invoices to authenticated;
grant execute on function scopes_probe.customer_ids_with(text), scopes_probe.organization_ids_with(text) to authenticated;

-- Organization A (…0a) has customers 42 and 43, organization B (…0b) customer 50.
insert into scopes_probe.quotes values
  (1, '00000000-0000-4000-8000-00000000000a', 42),
  (2, '00000000-0000-4000-8000-00000000000a', 42),
  (3, '00000000-0000-4000-8000-00000000000a', 43),
  (4, '00000000-0000-4000-8000-00000000000b', 50);
insert into scopes_probe.invoices values
  (1, '00000000-0000-4000-8000-00000000000a', 42),
  (2, '00000000-0000-4000-8000-00000000000a', 43),
  (3, '00000000-0000-4000-8000-00000000000b', 50);
-- The contact (…c1) may see customer 42's quotes and customer 43's invoices;
-- the employee (…e1) may see organization A's quotes and invoices.
insert into scopes_probe.scope_grants values
  ('00000000-0000-4000-8000-0000000000c1', 'customer', '42', 'quotes.view'),
  ('00000000-0000-4000-8000-0000000000c1', 'customer', '43', 'invoices.view'),
  ('00000000-0000-4000-8000-0000000000e1', 'organization', '00000000-0000-4000-8000-00000000000a', 'quotes.view'),
  ('00000000-0000-4000-8000-0000000000e1', 'organization', '00000000-0000-4000-8000-00000000000a', 'invoices.view');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}',
  true
);
set local role authenticated;

select results_eq(
  'select id from scopes_probe.quotes order by id',
  $$values (1::bigint), (2::bigint)$$,
  'a contact sees the quotes of the customer they may view quotes for'
);
select results_eq(
  'select id from scopes_probe.invoices order by id',
  $$values (2::bigint)$$,
  'a contact sees invoices only where they hold invoices.view'
);
select throws_ok(
  'select * from scopes_probe.scope_grants',
  '42501',
  null,
  'a contact cannot read the grants behind the helpers'
);
select is_empty(
  'select id from scopes_probe.quotes where customer_id = 43',
  'invoices.view on a customer does not open its quotes'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}',
  true
);
set local role authenticated;

select results_eq(
  'select id from scopes_probe.quotes order by id',
  $$values (1::bigint), (2::bigint), (3::bigint)$$,
  'an employee sees every quote of their organization'
);
select results_eq(
  'select id from scopes_probe.invoices order by id',
  $$values (1::bigint), (2::bigint)$$,
  'an employee sees every invoice of their organization'
);
select is_empty(
  $$select id from scopes_probe.quotes where organization_id = '00000000-0000-4000-8000-00000000000b'$$,
  'an employee sees nothing of another organization'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000ff","role":"authenticated"}',
  true
);
set local role authenticated;

select is_empty('select id from scopes_probe.quotes', 'a user without grants sees no quotes');

reset role;
-- `in (select helper())` runs each helper once per statement, as a hashed
-- SubPlan, rather than once per row.
create function scopes_probe.plan_of(query text) returns text
language plpgsql as $$
declare
  line text;
  plan text := '';
begin
  for line in execute 'explain ' || query loop
    plan := plan || line || E'\n';
  end loop;
  return plan;
end
$$;
set local role authenticated;
select matches(
  scopes_probe.plan_of('select id from scopes_probe.quotes'),
  'hashed SubPlan 1.* OR .*hashed SubPlan 2',
  'the policy calls each helper once per statement'
);

select * from finish();
rollback;
