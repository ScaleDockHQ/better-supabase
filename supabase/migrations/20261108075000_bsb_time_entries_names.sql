-- The time-tracking block is time-entries (ADR 0387): its registry row, its
-- permission keys (grants and overrides follow the permission row) and the
-- block name automations store. Renames only; no row is added or removed.
do $$
begin
  if to_regclass('better_supabase.blocks') is not null then
    update better_supabase.blocks set name = 'time-entries'
      where name = 'time-tracking'
        and not exists (select 1 from better_supabase.blocks where name = 'time-entries');
  end if;

  if to_regclass('better_supabase.permissions') is not null then
    update better_supabase.permissions p
      set key = 'time_entries.' || substr(p.key, length('time_tracking.') + 1)
      where p.key like 'time\_tracking.%'
        and not exists (
          select 1 from better_supabase.permissions q
          where q.key = 'time_entries.' || substr(p.key, length('time_tracking.') + 1)
        );
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'better_supabase' and table_name = 'automations' and column_name = 'block'
  ) then
    execute 'update better_supabase.automations set block = ''time-entries'' where block = ''time-tracking''';
  end if;
end
$$;
