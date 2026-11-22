-- better-supabase add --adopt: the rows and settings of tax that no data migration holds yet.

set lock_timeout = '5s';

-- tax
insert into better_supabase.blocks (name, version, mode)
values ('tax', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
