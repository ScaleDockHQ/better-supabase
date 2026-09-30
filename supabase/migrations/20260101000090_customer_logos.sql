-- Customer logos. customers.logo_path stores the object path, never a URL:
-- signed URLs expire and public URLs pin the project host. The bucket is
-- public for reads; writes stay within the tenant.
alter table public.customers add column logo_path text;

-- better-supabase: bucket customer-logos ({orgId}/{customerId}/logo/{version}.webp)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('customer-logos', 'customer-logos', true, 5242880, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "bs_customer_logos_select" on storage.objects;
create policy "bs_customer_logos_select" on storage.objects for select to authenticated
  using (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')));

drop policy if exists "bs_customer_logos_insert" on storage.objects;
create policy "bs_customer_logos_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$');

drop policy if exists "bs_customer_logos_update" on storage.objects;
create policy "bs_customer_logos_update" on storage.objects for update to authenticated
  using (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')))
  with check (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$');

drop policy if exists "bs_customer_logos_delete" on storage.objects;
create policy "bs_customer_logos_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')));
