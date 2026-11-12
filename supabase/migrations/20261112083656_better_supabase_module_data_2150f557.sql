-- better-supabase add --adopt: the rows and settings of webhooks-in that no data migration holds yet.

set lock_timeout = '5s';

-- webhooks-in
insert into better_supabase.blocks (name, version, mode)
values ('webhooks-in', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
