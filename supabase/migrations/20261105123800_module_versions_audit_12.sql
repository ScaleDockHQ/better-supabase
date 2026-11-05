-- better-supabase add --adopt: the audit block row at version 12.
insert into better_supabase.blocks (name, version, mode)
values ('audit', 12, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
