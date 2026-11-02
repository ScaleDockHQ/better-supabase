-- Records the module versions the DSA follow-up migration brings the database to,
-- so `better-supabase doctor` (BS311) sees them as current.

insert into better_supabase.blocks (name, version, mode)
values
  ('data-lifecycle', 9, 'managed'),
  ('moderation', 2, 'managed'),
  ('compliance', 4, 'managed'),
  ('incidents', 4, 'managed'),
  ('consents', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
