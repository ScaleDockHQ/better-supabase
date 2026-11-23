-- better-supabase add --adopt: the rows and settings of imports, inventory that no data migration holds yet.

set lock_timeout = '5s';

-- imports
insert into better_supabase.blocks (name, version, mode)
values ('imports', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- inventory
insert into better_supabase.blocks (name, version, mode)
values ('inventory', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
