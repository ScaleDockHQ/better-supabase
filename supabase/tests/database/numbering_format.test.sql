-- `{n:W}` pads to at least W digits and never cuts a wider number, so a
-- counter that outgrows its width keeps issuing unique numbers.
begin;
select plan(3);

select is(better_supabase.format_assigned_number('INV-{n:3}', 7, now()), 'INV-007', 'pads a narrow number');
select is(better_supabase.format_assigned_number('INV-{n:3}', 1000, now()), 'INV-1000', 'keeps every digit of a wider number');
select is(better_supabase.format_assigned_number('{n:0}', 42, now()), '42', 'a zero width writes the number');

select * from finish();
rollback;
