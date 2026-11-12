-- better-supabase add --adopt: the rows and settings of billing that no data migration holds yet.

set lock_timeout = '5s';

-- billing
insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
