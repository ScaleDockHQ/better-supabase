-- better-supabase add --adopt: the rows and settings of messaging that no data migration holds yet.

set lock_timeout = '5s';

-- messaging
insert into better_supabase.blocks (name, version, mode)
values ('messaging', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
