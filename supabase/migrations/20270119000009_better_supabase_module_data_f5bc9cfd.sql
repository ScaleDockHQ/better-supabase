-- better-supabase add --adopt: the rows and settings of webhooks that no data migration holds yet.

set lock_timeout = '5s';

-- webhooks
insert into better_supabase.blocks (name, version, mode)
values ('webhooks', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
