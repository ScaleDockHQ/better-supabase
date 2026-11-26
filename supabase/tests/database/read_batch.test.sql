-- read_batch runs several stable reads in one call, each as the caller, and
-- skips anything it may not dispatch: a volatile function, one outside the API
-- schema, one that returns no jsonb, or arguments it doesn't declare. An error
-- stays with its entry, and RLS still decides what each read returns. The
-- owner (…00a1) runs Acme (…0001) (supabase/seed.sql).
begin;
select plan(11);

create function api.rb_double(n integer, plus integer default 0)
returns jsonb language sql stable as $$ select to_jsonb(n * 2 + plus) $$;

create function api.rb_none()
returns jsonb language sql stable as $$ select '"none"'::jsonb $$;

create function api.rb_volatile()
returns jsonb language sql volatile as $$ select '"wrote"'::jsonb $$;

create function api.rb_text()
returns text language sql stable as $$ select 'text' $$;

create function api.rb_fails()
returns jsonb language plpgsql stable as $$
begin
  raise exception 'no read' using errcode = '22023', hint = 'RB_FAILS', detail = 'why';
end;
$$;

create function api.rb_private()
returns jsonb language sql stable as $$ select '"private"'::jsonb $$;
revoke execute on function api.rb_private() from public, anon, authenticated;

create function better_supabase.rb_internal()
returns jsonb language sql stable as $$ select '"internal"'::jsonb $$;
grant execute on function better_supabase.rb_internal() to authenticated;

create table api.rb_rows (owner uuid not null, label text not null);
alter table api.rb_rows enable row level security;
create policy rb_rows_own on api.rb_rows for select to authenticated using (owner = auth.uid());
grant select on api.rb_rows to authenticated;
insert into api.rb_rows values
  ('00000000-0000-4000-8000-0000000000a1', 'mine'),
  ('00000000-0000-4000-8000-0000000000a2', 'theirs');

create function api.rb_labels()
returns jsonb language sql stable security invoker as $$
  select coalesce(jsonb_agg(label order by label), '[]'::jsonb) from api.rb_rows
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.read_batch('[{"fn":"rb_double","args":{"n":2}},{"fn":"rb_double","args":{"n":5,"plus":1}},{"fn":"rb_none"}]'),
  '[{"data":4},{"data":11},{"data":"none"}]'::jsonb,
  'two stable reads and a read without arguments come back in order'
);

select is(
  api.read_batch('[{"fn":"rb_volatile"},{"fn":"rb_none","args":{}}]'),
  '[{"skipped":true},{"data":"none"}]'::jsonb,
  'a volatile function is skipped, so the client calls it on its own'
);

select is(
  api.read_batch('[{"fn":"rb_internal"},{"fn":"read_batch","args":{"calls":[]}},{"fn":"rb_text"}]'),
  '[{"skipped":true},{"skipped":true},{"skipped":true}]'::jsonb,
  'a function outside the API schema, read_batch itself and a non-jsonb function are skipped'
);

select is(
  api.read_batch('[{"fn":"rb_double","args":{"n":1,"other":2}},{"fn":"rb_double","args":{"plus":1}},{"fn":"rb_missing"}]'),
  '[{"skipped":true},{"skipped":true},{"skipped":true}]'::jsonb,
  'an undeclared argument, a missing required one and an unknown function are skipped'
);

select is(
  api.read_batch('[{"fn":"rb_fails"},{"fn":"rb_double","args":{"n":3}}]'),
  '[{"error":{"code":"22023","message":"no read","details":"why","hint":"RB_FAILS"}},{"data":6}]'::jsonb,
  'an error stays with its entry, and the next read still runs'
);

select is(
  api.read_batch('[{"fn":"rb_private"}]') -> 0 -> 'error' ->> 'code',
  '42501',
  'a function the caller may not execute answers its permission error'
);

select is(
  api.read_batch('[{"fn":"rb_double","args":{"n":"x"}}]') -> 0 -> 'error' ->> 'code',
  '22P02',
  'an argument of the wrong type is that entry''s error'
);

select is(
  api.read_batch('[{"fn":"rb_labels"}]'),
  '[{"data":["mine"]}]'::jsonb,
  'RLS still applies: the owner reads only its own rows'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  api.read_batch('[{"fn":"rb_labels"}]'),
  '[{"data":["theirs"]}]'::jsonb,
  'another caller reads its own rows through the same batch'
);

select throws_ok(
  $$ select api.read_batch('{"fn":"rb_none"}') $$,
  '22023',
  null,
  'input that is not an array is refused'
);

select throws_ok(
  format(
    $f$ select api.read_batch(%L) $f$,
    (select jsonb_agg(jsonb_build_object('fn', 'rb_none')) from generate_series(1, 51))
  ),
  '54000',
  null,
  'more than 50 calls are refused'
);

select * from finish();
rollback;
