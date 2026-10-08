-- Customer logos. The bucket row is data, so the baseline migration inserts it;
-- the bucket is public for reads and writes stay within the tenant.
create policy "bs_customer_logos_select" on storage.objects for select to authenticated
  using (bucket_id = 'customer-logos' and name collate "C" >= ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '/') and name collate "C" < ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '0') and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')));

create policy "bs_customer_logos_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'customer-logos' and name collate "C" >= ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '/') and name collate "C" < ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '0') and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$');

create policy "bs_customer_logos_update" on storage.objects for update to authenticated
  using (bucket_id = 'customer-logos' and name collate "C" >= ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '/') and name collate "C" < ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '0') and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')))
  with check (bucket_id = 'customer-logos' and name collate "C" >= ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '/') and name collate "C" < ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '0') and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\.webp$');

create policy "bs_customer_logos_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'customer-logos' and name collate "C" >= ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '/') and name collate "C" < ((coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) || '0') and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')));

-- Profile pictures (`avatarBucket()`): public for reads, and each user writes
-- only under their own id. The bucket row is data, so a migration inserts it.
create policy "bs_avatars_select" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and name collate "C" >= ((select auth.uid())::text || '/') and name collate "C" < ((select auth.uid())::text || '0') and split_part(name, '/', 1) = (select auth.uid())::text);

create policy "bs_avatars_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and name collate "C" >= ((select auth.uid())::text || '/') and name collate "C" < ((select auth.uid())::text || '0') and split_part(name, '/', 1) = (select auth.uid())::text and name ~ '^[^/]+/avatar-[^/]+\.[^/]+$');

create policy "bs_avatars_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and name collate "C" >= ((select auth.uid())::text || '/') and name collate "C" < ((select auth.uid())::text || '0') and split_part(name, '/', 1) = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and name collate "C" >= ((select auth.uid())::text || '/') and name collate "C" < ((select auth.uid())::text || '0') and split_part(name, '/', 1) = (select auth.uid())::text and name ~ '^[^/]+/avatar-[^/]+\.[^/]+$');

create policy "bs_avatars_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and name collate "C" >= ((select auth.uid())::text || '/') and name collate "C" < ((select auth.uid())::text || '0') and split_part(name, '/', 1) = (select auth.uid())::text);
