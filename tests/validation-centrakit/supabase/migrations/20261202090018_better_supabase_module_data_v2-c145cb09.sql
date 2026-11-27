-- better-supabase add --adopt: the rows and settings of notifications that no data migration holds yet.

set lock_timeout = '5s';

-- notifications
insert into better_supabase.blocks (name, version, mode)
values ('notifications', 12, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
