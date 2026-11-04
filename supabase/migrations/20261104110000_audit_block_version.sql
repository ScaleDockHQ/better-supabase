-- better-supabase module: audit
insert into better_supabase.blocks (name, version, mode)
values ('audit', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
