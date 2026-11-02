set lock_timeout = '5s';

insert into better_supabase.blocks (name, version, mode)
values
  ('usage', 7, 'managed'),
  ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
