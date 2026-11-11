-- better-supabase add --adopt: the rows and settings of leave that no data migration holds yet.

set lock_timeout = '5s';

-- leave
insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
