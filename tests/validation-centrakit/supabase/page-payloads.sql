-- CentraKit's customer page, before and after the split that lets its tenant
-- rows live in one share: "tenant" cache entry. src/page-payloads.test.ts
-- loads this file inside a transaction it rolls back.

create schema app_auth;
grant usage on schema app_auth to authenticated;

-- The organizations where the caller holds a permission, under the app's own
-- name so payloads don't call the provider's helpers directly.
create function app_auth.allowed_org_ids(key text)
returns setof uuid
language sql
stable
as $$
  select centrakit.authz_organization_ids_with(key)
$$;
grant execute on function app_auth.allowed_org_ids(text) to authenticated;

-- Before: the organization's customers and the caller's starred ones in one
-- payload, so every caller needs an entry of their own.
create function public.customer_page_payload(org uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'customers', (
      select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.company_name) order by c.company_name), '[]')
      from centrakit.customers c
      where c.organization_id = org
    ),
    'starred', (
      select coalesce(jsonb_agg(s.subject_id order by s.subject_id), '[]')
      from centrakit.subject_user_state s
      where s.subject_type = 'customer'
        and s.user_id = (select auth.uid())
        and s.starred_at is not null
    )
  )
$$;

-- After, shared: the organization's customers, filtered the way the
-- customers select policy filters them.
create function public.customer_list_payload(org uuid)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.company_name) order by c.company_name), '[]')
  from centrakit.customers c
  where c.organization_id = org
    and c.organization_id in (select app_auth.allowed_org_ids('crm.read'))
$$;

-- After, per user: the caller's starred customers, read outside the shared
-- entry.
create function public.customer_starred(org uuid)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(s.subject_id order by s.subject_id), '[]')
  from centrakit.subject_user_state s
  join centrakit.customers c on c.id::text = s.subject_id
  where s.subject_type = 'customer'
    and s.user_id = (select auth.uid())
    and s.starred_at is not null
    and c.organization_id = org
$$;

grant execute on function public.customer_page_payload(uuid),
  public.customer_list_payload(uuid), public.customer_starred(uuid)
  to authenticated;
