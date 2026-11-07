-- A soft-deleted block row carries archived_at (ADR 0346). Renames only: no row
-- moves. A table or column the project doesn't have is skipped.
do $$
declare
  r record;
begin
  for r in
    select * from (values
    ('drive_nodes', 'deleted_at', 'archived_at'),
    ('memories', 'deleted_at', 'archived_at'),
    ('messages', 'deleted_at', 'archived_at')
    ) as renames (table_name, old_name, new_name)
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'better_supabase' and table_name = r.table_name and column_name = r.old_name
    ) then
      execute format('alter table better_supabase.%I rename column %I to %I', r.table_name, r.old_name, r.new_name);
    end if;
  end loop;
end
$$;
