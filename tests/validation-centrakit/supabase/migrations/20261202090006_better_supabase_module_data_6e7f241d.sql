-- better-supabase add --adopt: the rows and settings of queue, webhook-inbox, outbox, comments, imports, subjects that no data migration holds yet.

set lock_timeout = '5s';

-- queue
insert into better_supabase.blocks (name, version, mode)
values ('queue', 13, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhook-inbox
insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 11, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- outbox
insert into better_supabase.blocks (name, version, mode)
values ('outbox', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- comments
insert into better_supabase.blocks (name, version, mode)
values ('comments', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- imports
insert into better_supabase.blocks (name, version, mode)
values ('imports', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- subjects
insert into better_supabase.blocks (name, version, mode)
values ('subjects', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
