-- better-supabase add --adopt: the rows and settings of audit, imports that no data migration holds yet.

set lock_timeout = '5s';

-- audit
insert into better_supabase.blocks (name, version, mode)
values ('audit', 16, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- imports
insert into better_supabase.blocks (name, version, mode)
values ('imports', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
