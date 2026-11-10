-- The SQL that the @bsb list, access and idempotency tags render for a table (ADR 0637),
-- applied and called. tests/sql/tag-statements.test.ts renders the same blocks and
-- compares them with this file's text, so the two cannot drift.
begin;
select plan(7);
create extension if not exists pg_trgm with schema extensions;
create table public.scale_items (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, title text not null, status text not null default 'open', created_at timestamptz not null default now(), idempotency_key text);
-- @bsb-tag list begin
-- Keyset page of public.scale_items: filters is { search, status, limit, after, offset, paged, total, totalCap }; row security decides the rows.
create or replace function "public"."list_scale_items"(tenant uuid default null, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_scale_items.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "public"."scale_items" x
      where (list_scale_items.tenant is null or x."tenant_id" = list_scale_items.tenant)
        and (not v_filters ? 'status' or x."status" = (v_filters ->> 'status')::text)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "public"."scale_items" x
      where (list_scale_items.tenant is null or x."tenant_id" = list_scale_items.tenant)
        and (not v_filters ? 'status' or x."status" = (v_filters ->> 'status')::text)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "public"."list_scale_items"(uuid, jsonb) from public;
grant execute on function "public"."list_scale_items"(uuid, jsonb) to authenticated, service_role;
create index "bsb_scale_items_list_idx" on "public"."scale_items" ("tenant_id", "created_at" desc, "id");
create index "bsb_scale_items_title_trgm_idx" on "public"."scale_items" using gin ("title" extensions.gin_trgm_ops);
-- @bsb-tag list end
-- @bsb-tag access begin
alter table "public"."scale_items" enable row level security;
create policy "bsb_access_scale_items_read" on "public"."scale_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('items.read')));
create policy "bsb_access_scale_items_create" on "public"."scale_items"
  for insert to authenticated
  with check ("tenant_id" in (select better_supabase.tenant_ids_with('items.write')) and (better_supabase.actor_may_write()));
create policy "bsb_access_scale_items_update" on "public"."scale_items"
  for update to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('items.write')) and (better_supabase.actor_may_write()))
  with check ("tenant_id" in (select better_supabase.tenant_ids_with('items.write')) and (better_supabase.actor_may_write()));
create policy "bsb_access_scale_items_delete" on "public"."scale_items"
  for delete to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('items.write')) and (better_supabase.actor_may_write()));
-- @bsb-tag access end
-- @bsb-tag idempotency begin
create unique index "bsb_scale_items_idempotency_key" on "public"."scale_items" ("tenant_id", "idempotency_key") where "idempotency_key" is not null;
-- @bsb-tag idempotency end
insert into public.scale_items (tenant_id, title, status, created_at)
select '00000000-0000-4000-8000-000000000001', 'Item ' || g, case when g % 3 = 0 then 'done' else 'open' end, now() - (g || ' minutes')::interval from generate_series(1, 100) g;
grant all on public.scale_items to service_role;
set local role service_role;
select public.list_scale_items('00000000-0000-4000-8000-000000000001', '{"limit":10,"paged":true,"total":true}') as p1 \gset
select is(jsonb_array_length(:'p1'::jsonb -> 'items'), 10, 'first page');
select is((:'p1'::jsonb ->> 'total')::int, 100, 'total');
select public.list_scale_items('00000000-0000-4000-8000-000000000001', jsonb_build_object('limit',10,'paged',true,'after', (:'p1'::jsonb) -> 'nextCursor')) as p2 \gset
select is((:'p2'::jsonb -> 'items' -> 0 ->> 'title'), 'Item 11', 'second page by keyset starts after the cursor');
select is(jsonb_array_length(public.list_scale_items('00000000-0000-4000-8000-000000000001', '{"status":"done","limit":100}')), 33, 'filter');
select is(jsonb_array_length(public.list_scale_items(null, '{"search":"Item 1","limit":100}')), 12, 'search');
select is((public.list_scale_items(null, '{"limit":5,"offset":95}') -> 0 ->> 'title'), 'Item 96', 'offset');
reset role;
select is((select count(*)::int from pg_policies where tablename='scale_items'), 4, 'policies');
select * from finish();
rollback;
