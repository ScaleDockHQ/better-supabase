-- better-supabase add --adopt: the rows and settings of attachments that no data migration holds yet.

set lock_timeout = '5s';

-- attachments
insert into better_supabase.blocks (name, version, mode)
values ('attachments', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
