-- The bulk block is bulk-actions (ADR 0388): its registry row, its permission
-- keys (grants and overrides follow the permission row) and the block name
-- automations store. Renames only; no row is added or removed.
do $$
begin
  if to_regclass('better_supabase.blocks') is not null then
    update better_supabase.blocks set name = 'bulk-actions'
      where name = 'bulk'
        and not exists (select 1 from better_supabase.blocks where name = 'bulk-actions');
  end if;

  if to_regclass('better_supabase.permissions') is not null then
    update better_supabase.permissions p
      set key = 'bulk_actions.' || substr(p.key, length('bulk.') + 1)
      where p.key like 'bulk.%'
        and not exists (
          select 1 from better_supabase.permissions q
          where q.key = 'bulk_actions.' || substr(p.key, length('bulk.') + 1)
        );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'better_supabase' and table_name = 'automations' and column_name = 'block'
  ) then
    execute 'update better_supabase.automations set block = ''bulk-actions'' where block = ''bulk''';
  end if;
end
$$;
