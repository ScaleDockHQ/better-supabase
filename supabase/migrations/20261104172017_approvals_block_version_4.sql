-- better-supabase add --adopt: the approvals block row at version 4.
insert into better_supabase.blocks (name, version, mode)
values ('approvals', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
