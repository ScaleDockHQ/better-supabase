-- better-supabase add --adopt: the audit, approvals and tasks block rows at the 0.54 versions.
insert into better_supabase.blocks (name, version, mode)
values ('audit', 11, 'managed'), ('approvals', 5, 'managed'), ('tasks', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
