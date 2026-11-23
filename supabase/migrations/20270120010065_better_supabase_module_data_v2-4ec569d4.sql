-- better-supabase add --adopt: the rows and settings of orders that no data migration holds yet.

set lock_timeout = '5s';

-- orders
insert into better_supabase.blocks (name, version, mode)
values ('orders', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
