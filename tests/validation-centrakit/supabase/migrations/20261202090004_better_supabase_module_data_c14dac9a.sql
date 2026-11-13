-- better-supabase add --adopt: the rows and settings of impersonation that no data migration holds yet.

set lock_timeout = '5s';

-- impersonation
insert into better_supabase.blocks (name, version, mode)
values ('impersonation', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
