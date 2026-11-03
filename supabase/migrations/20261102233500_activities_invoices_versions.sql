set lock_timeout = '5s';

insert into better_supabase.blocks (name, version, mode)
values
  ('activities', 4, 'managed'),
  ('invoices', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
