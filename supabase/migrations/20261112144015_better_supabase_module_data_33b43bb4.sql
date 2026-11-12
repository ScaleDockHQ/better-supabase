-- better-supabase add --adopt: the rows and settings of mfa, impersonation, identities, vercel-marketplace, advisories that no data migration holds yet.

set lock_timeout = '5s';

-- mfa
insert into better_supabase.blocks (name, version, mode)
values ('mfa', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- impersonation
insert into better_supabase.blocks (name, version, mode)
values ('impersonation', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- identities
insert into better_supabase.blocks (name, version, mode)
values ('identities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- vercel-marketplace
insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- advisories
insert into better_supabase.blocks (name, version, mode)
values ('advisories', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
