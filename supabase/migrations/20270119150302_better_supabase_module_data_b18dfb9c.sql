-- better-supabase add --adopt: the rows and settings of time-entries that no data migration holds yet.

set lock_timeout = '5s';

-- time-entries
insert into better_supabase.blocks (name, version, mode)
values ('time-entries', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
