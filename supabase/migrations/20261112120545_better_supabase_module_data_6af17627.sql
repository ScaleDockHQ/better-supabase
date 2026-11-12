-- better-supabase add --adopt: the rows and settings of webhook-inbox that no data migration holds yet.

set lock_timeout = '5s';

-- webhook-inbox
insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
