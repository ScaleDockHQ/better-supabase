-- better-supabase add --adopt: the approvals block row at version 3.
insert into better_supabase.blocks (name, version, mode)
values ('approvals', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
