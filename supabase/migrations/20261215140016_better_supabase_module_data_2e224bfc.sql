-- better-supabase add --adopt: the rows and settings of usage, comments, subjects, search that no data migration holds yet.

set lock_timeout = '5s';

-- usage
insert into better_supabase.blocks (name, version, mode)
values ('usage', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- comments
insert into better_supabase.blocks (name, version, mode)
values ('comments', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- subjects
insert into better_supabase.blocks (name, version, mode)
values ('subjects', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- search
insert into better_supabase.blocks (name, version, mode)
values ('search', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
