-- better-supabase add --adopt: the rows and settings of tasks, tasks that no data migration holds yet.

set lock_timeout = '5s';

-- tasks
insert into better_supabase.blocks (name, version, mode)
values ('tasks', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- tasks
insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 8, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();
