update better_supabase.import_runs
set status = 'completed', finished_at = now(), outcome = 'seeded'
where id = '00000000-0000-4000-8000-5ca1e5eed000';
