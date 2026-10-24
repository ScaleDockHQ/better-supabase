-- Block SQL writes text into the app's own status columns through
-- better_supabase.as_column_type, so an enum or a domain column takes the
-- value, and a value the type rejects fails as it would on a direct insert.
begin;
select plan(8);

create type public.test_ticket_status as enum ('open', 'closed');
create domain public.test_priority as text check (value in ('low', 'high'));
create table public.test_tickets (
  id bigint generated always as identity primary key,
  status public.test_ticket_status not null default 'open',
  priority public.test_priority not null default 'low'
);

select is(
  pg_typeof(better_supabase.as_column_type('closed', (null::public.test_tickets).status))::text,
  'test_ticket_status',
  'as_column_type returns the enum of the target column'
);

select is(
  pg_typeof(better_supabase.as_column_type('high', (null::public.test_tickets).priority))::text,
  'test_priority',
  'as_column_type returns the domain of the target column'
);

select lives_ok(
  $$insert into public.test_tickets (status, priority)
    values (
      better_supabase.as_column_type('closed', (null::public.test_tickets).status),
      better_supabase.as_column_type('high', (null::public.test_tickets).priority)
    )$$,
  'text from a block writes into an enum and a domain column'
);

select results_eq(
  $$select status::text, priority::text from public.test_tickets$$,
  $$values ('closed', 'high')$$,
  'the enum and the domain keep the written values'
);

select lives_ok(
  $$update public.test_tickets
    set status = better_supabase.as_column_type(case when true then 'open' else 'closed' end, (null::public.test_tickets).status)$$,
  'a computed text value updates the enum column'
);

select ok(
  (select status::text = any (array['open']) from public.test_tickets),
  'the enum compares against text through ::text'
);

select throws_ok(
  $$update public.test_tickets
    set status = better_supabase.as_column_type('archived', (null::public.test_tickets).status)$$,
  '22P02',
  null,
  'a value outside the enum fails like a direct write'
);

select throws_ok(
  $$update public.test_tickets
    set priority = better_supabase.as_column_type('urgent', (null::public.test_tickets).priority)$$,
  '23514',
  null,
  'a value the domain check rejects fails like a direct write'
);

select * from finish();
rollback;
