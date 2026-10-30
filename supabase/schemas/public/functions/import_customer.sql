-- Fixture import target for `imports.options.targets.customer`. The imports
-- module calls it as its owner, so it writes without RLS; the module has
-- already checked the run's tenant. Returns the subject it wrote.
create or replace function public.import_customer(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if subject_id is null then
    insert into public.customers (organization_id, name, kvk, status)
    values (
      (item ->> 'tenant')::uuid,
      item -> 'data' ->> 'name',
      item -> 'data' ->> 'kvk',
      coalesce(item -> 'data' ->> 'status', 'lead')
    )
    returning id into v_id;
  else
    update public.customers c
    set name = item -> 'data' ->> 'name',
        kvk = item -> 'data' ->> 'kvk',
        status = coalesce(item -> 'data' ->> 'status', c.status)
    where c.id = subject_id::uuid
    returning c.id into v_id;
  end if;

  return jsonb_build_object(
    'subjectId', v_id::text,
    'updatedAt', (select c.updated_at from public.customers c where c.id = v_id)
  );
end;
$$;

revoke execute on function public.import_customer(uuid, jsonb, text) from public, anon, authenticated;

grant execute on function public.import_customer(uuid, jsonb, text) to service_role;

-- When the customer last changed, so an import leaves a row a user edited alone.
create or replace function public.import_customer_updated_at(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select c.updated_at from public.customers c where c.id = subject_id::uuid;
$$;

revoke execute on function public.import_customer_updated_at(text) from public, anon, authenticated;

grant execute on function public.import_customer_updated_at(text) to service_role;
