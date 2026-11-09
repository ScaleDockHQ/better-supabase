-- Fixture batch target for `imports.options.targets.customer.batch`: the set
-- form of public.import_customer. One statement inserts the new customers and one
-- updates the changed ones; the answer has one entry per item, in order. It
-- raises when a row is refused, and the imports module then runs every item
-- through public.import_customer on its own.
create or replace function public.import_customer_batch(run uuid, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_out jsonb;
begin
  with src as (
    select
      e.ordinality::int as i,
      e.value as item,
      coalesce(e.value ->> 'subjectId', gen_random_uuid()::text)::uuid as id,
      (e.value ->> 'subjectId') is null as is_new
    from jsonb_array_elements(items) with ordinality e(value, ordinality)
  ),
  ins as (
    insert into public.customers (id, organization_id, name, kvk, status)
    select
      s.id,
      (s.item ->> 'tenant')::uuid,
      s.item -> 'data' ->> 'name',
      s.item -> 'data' ->> 'kvk',
      coalesce(s.item -> 'data' ->> 'status', 'lead')
    from src s
    where s.is_new
    returning id, updated_at
  ),
  upd as (
    update public.customers c
    set name = s.item -> 'data' ->> 'name',
        kvk = s.item -> 'data' ->> 'kvk',
        status = coalesce(s.item -> 'data' ->> 'status', c.status)
    from src s
    where not s.is_new and c.id = s.id
    returning c.id, c.updated_at
  ),
  written as (
    select id, updated_at from ins
    union all
    select id, updated_at from upd
  )
  select coalesce(jsonb_agg(
    case when w.id is null
      then jsonb_build_object('error', jsonb_build_object('code', 'IMPORT_ITEM_INVALID', 'message', 'the customer no longer exists'))
      else jsonb_build_object('subjectId', s.id::text, 'updatedAt', w.updated_at)
    end order by s.i), '[]'::jsonb)
  into v_out
  from src s
  left join written w on w.id = s.id;

  return v_out;
end;
$$;

revoke execute on function public.import_customer_batch(uuid, jsonb) from public, anon, authenticated;

grant execute on function public.import_customer_batch(uuid, jsonb) to service_role;
