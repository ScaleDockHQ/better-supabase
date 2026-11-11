-- The SQL that the @bsb buckets tag renders for a table (ADR 0672), applied and called.
-- tests/sql/tag-statements.test.ts renders the same block and compares it with this file's text,
-- so the two cannot drift.
begin;
select plan(9);
create table public.scale_events (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, kind text not null, status text, occurred_at timestamptz not null);
-- @bsb-tag buckets begin
-- The rows of public.scale_events per date bucket of occurred_at (at most 1000 buckets); row security decides the rows.
create or replace function "public"."scale_events_date_buckets"(unit text, tz text default 'UTC', from_at timestamptz default null, to_at timestamptz default null, equals jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if scale_events_date_buckets.unit is null or scale_events_date_buckets.unit not in ('hour', 'day', 'week', 'month', 'quarter', 'year') then
    raise exception 'unit must be hour, day, week, month, quarter or year' using errcode = '22023';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('bucket', b.bucket, 'count', b.n) order by b.bucket), '[]'::jsonb)
    from (
      select date_trunc(scale_events_date_buckets.unit, x."occurred_at"::timestamptz, scale_events_date_buckets.tz) as bucket, count(*) as n
      from "public"."scale_events" x
      where (scale_events_date_buckets.from_at is null or x."occurred_at" >= scale_events_date_buckets.from_at)
        and (scale_events_date_buckets.to_at is null or x."occurred_at" < scale_events_date_buckets.to_at)
        and (not (scale_events_date_buckets.equals ? 'kind') or x."kind"::text in (select jsonb_array_elements_text(scale_events_date_buckets.equals -> 'kind')))
        and (not (scale_events_date_buckets.equals ? 'status') or x."status"::text in (select jsonb_array_elements_text(scale_events_date_buckets.equals -> 'status')))
      group by 1
      order by 1
      limit 1000
    ) b
  );
end;
$$;
revoke execute on function "public"."scale_events_date_buckets"(text, text, timestamptz, timestamptz, jsonb) from public;
grant execute on function "public"."scale_events_date_buckets"(text, text, timestamptz, timestamptz, jsonb) to authenticated, service_role;
-- @bsb-tag buckets end
insert into public.scale_events (tenant_id, kind, status, occurred_at) values
  ('00000000-0000-4000-8000-000000000001', 'call', 'open', '2026-01-01 23:30:00+00'),
  ('00000000-0000-4000-8000-000000000001', 'call', 'done', '2026-01-02 00:30:00+00'),
  ('00000000-0000-4000-8000-000000000001', 'visit', 'open', '2026-01-02 12:00:00+00'),
  ('00000000-0000-4000-8000-000000000001', 'visit', null, '2026-02-10 12:00:00+00');
select is(public.scale_events_date_buckets('day') -> 0 ->> 'count', '1', 'the first day holds one row');
select is(jsonb_array_length(public.scale_events_date_buckets('day')), 3, 'three days hold rows');
select is(jsonb_array_length(public.scale_events_date_buckets('month')), 2, 'two months hold rows');
select is(public.scale_events_date_buckets('month') -> 0 ->> 'count', '3', 'January holds three rows');
select is(public.scale_events_date_buckets('day', 'Europe/Amsterdam') -> 0 ->> 'count', '3', 'the time zone moves a row across midnight');
select is(jsonb_array_length(public.scale_events_date_buckets('day', 'UTC', '2026-01-02', '2026-01-03')), 1, 'the range keeps one day');
select is(public.scale_events_date_buckets('month', 'UTC', null, null, '{"kind": ["call"]}') -> 0 ->> 'count', '2', 'a filter column narrows the rows');
select is(public.scale_events_date_buckets('month', 'UTC', null, null, '{"kind": ["visit"], "status": ["open"]}') -> 0 ->> 'count', '1', 'filters combine');
select throws_ok($$select public.scale_events_date_buckets('decade')$$, '22023', 'unit must be hour, day, week, month, quarter or year', 'an unknown unit is refused');
select * from finish();
rollback;
