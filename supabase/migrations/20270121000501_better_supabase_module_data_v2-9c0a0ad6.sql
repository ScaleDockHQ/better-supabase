-- better-supabase add --adopt: the rows and settings of notifications, tasks, tasks, collections that no data migration holds yet.

set lock_timeout = '5s';

-- notifications
insert into better_supabase.blocks (name, version, mode)
values ('notifications', 12, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tasks
insert into better_supabase.blocks (name, version, mode)
values ('tasks', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tasks
insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 10, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();

-- collections
insert into better_supabase.blocks (name, version, mode)
values ('collections', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
