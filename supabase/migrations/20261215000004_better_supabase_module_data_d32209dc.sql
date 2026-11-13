-- better-supabase add --adopt: the rows and settings of impersonation, billing, vercel-marketplace, field-encryption that no data migration holds yet.

set lock_timeout = '5s';

-- impersonation
insert into better_supabase.blocks (name, version, mode)
values ('impersonation', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- billing
insert into better_supabase.blocks (name, version, mode)
values ('billing', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- vercel-marketplace
insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- field-encryption
insert into better_supabase.blocks (name, version, mode)
values ('field-encryption', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
