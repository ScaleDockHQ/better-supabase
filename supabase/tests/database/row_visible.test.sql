-- row_visible() answers whether the calling API role sees a row through the
-- table's select policies: permissive ones or-ed, restrictive ones and-ed, the
-- select grant required, and a role that bypasses RLS sees every row.
begin;
select plan(7);

create table public.row_visible_notes (id uuid primary key, owner_id uuid, hidden boolean not null default false);
alter table public.row_visible_notes enable row level security;
revoke all on public.row_visible_notes from anon;
grant select on public.row_visible_notes to authenticated, service_role;
create policy row_visible_own on public.row_visible_notes for select to authenticated
  using (owner_id = (select auth.uid()));
create policy row_visible_shown on public.row_visible_notes as restrictive for select to authenticated
  using (not hidden);
create table public.row_visible_open (id uuid primary key);
revoke all on public.row_visible_open from anon;
grant select on public.row_visible_open to authenticated;
insert into public.row_visible_notes values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', false),
  ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a2', false),
  ('00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000a1', true);
insert into public.row_visible_open values ('00000000-0000-4000-8000-0000000000c1');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
select is(better_supabase.row_visible('public.row_visible_notes', 'id', '00000000-0000-4000-8000-0000000000b1'::uuid), true, 'a permissive policy shows the own row');
select is(better_supabase.row_visible('public.row_visible_notes', 'id', '00000000-0000-4000-8000-0000000000b2'::uuid), false, 'no policy shows another user''s row');
select is(better_supabase.row_visible('public.row_visible_notes', 'id', '00000000-0000-4000-8000-0000000000b3'::uuid), false, 'a restrictive policy hides the own hidden row');
select is(better_supabase.row_visible('public.row_visible_notes', 'id', '00000000-0000-4000-8000-0000000000b9'::uuid), false, 'a missing row is not visible');
select is(better_supabase.row_visible('public.row_visible_open', 'id', '00000000-0000-4000-8000-0000000000c1'::uuid), true, 'a table without row security shows its rows to a role with select');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(better_supabase.row_visible('public.row_visible_open', 'id', '00000000-0000-4000-8000-0000000000c1'::uuid), false, 'a role without the select grant sees nothing');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(better_supabase.row_visible('public.row_visible_notes', 'id', '00000000-0000-4000-8000-0000000000b2'::uuid), true, 'the service role bypasses row security');

select * from finish();
rollback;
