-- better-supabase add --adopt: the rows and settings of workflow-sdk, inbox, ai-schedules that no data migration holds yet.

set lock_timeout = '5s';

-- workflow-sdk
insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- inbox
insert into better_supabase.blocks (name, version, mode)
values ('inbox', 11, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ai-schedules
insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
