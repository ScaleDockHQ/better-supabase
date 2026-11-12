-- better-supabase add --adopt: the rows and settings of queue, webhook-inbox, outbox, notifications, webhooks-out that no data migration holds yet.

set lock_timeout = '5s';

-- queue
insert into better_supabase.blocks (name, version, mode)
values ('queue', 12, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhook-inbox
insert into better_supabase.blocks (name, version, mode)
values ('webhook-inbox', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- outbox
insert into better_supabase.blocks (name, version, mode)
values ('outbox', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- notifications
insert into better_supabase.blocks (name, version, mode)
values ('notifications', 11, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- webhooks-out
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-out', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
