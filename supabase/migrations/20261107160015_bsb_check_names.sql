-- Every check constraint a block adds is named bsb_*. Renames only: no row moves.
do $$
declare
  c record;
begin
  for c in
    select n.nspname as schema_name, r.relname as table_name, k.conname as name
    from pg_catalog.pg_constraint k
      join pg_catalog.pg_class r on r.oid = k.conrelid
      join pg_catalog.pg_namespace n on n.oid = r.relnamespace
    where n.nspname in ('better_supabase', 'workflow') and k.contype = 'c' and k.conname !~ '^bsb_'
  loop
    execute format('alter table %I.%I rename constraint %I to %I', c.schema_name, c.table_name, c.name, 'bsb_' || c.name);
  end loop;
end
$$;
