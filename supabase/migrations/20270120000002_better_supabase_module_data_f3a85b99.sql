-- better-supabase add --adopt: the rows and settings of ledger that no data migration holds yet.

set lock_timeout = '5s';

-- ledger
insert into better_supabase.blocks (name, version, mode)
values ('ledger', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
