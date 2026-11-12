-- Rows and settings of the fixture schema that a schema diff skips. The
-- module rows come from `better-supabase sql data` in the next migration.

insert into rbac.role_permissions (role, permission) values
  ('admin', 'audit.read'),
  ('admin', 'billing.manage'),
  ('admin', 'customers.read'),
  ('admin', 'customers.write'),
  ('admin', 'reports.read'),
  ('admin', 'settings.manage'),
  ('admin', 'users.manage'),
  ('member', 'customers.read')
on conflict do nothing;

-- better-supabase: bucket customer-logos ({orgId}/{customerId}/logo/{version}.webp)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('customer-logos', 'customer-logos', true, 5242880, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- better-supabase: bucket avatars ({userId}/avatar-{version}.{ext})
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/avif'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- `aggregate()` and `_sum`/`_avg`/`_min`/`_max` includes need PostgREST
-- aggregates, which are off by default (doctor BS210).
alter role authenticator set pgrst.db_aggregates_enabled = 'true';
notify pgrst, 'reload config';
