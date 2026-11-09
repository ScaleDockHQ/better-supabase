-- better-supabase add --adopt: the rows and settings of bulk-actions, time-entries that no data migration holds yet.

set lock_timeout = '5s';

-- bulk-actions
delete from better_supabase.blocks
  where name = 'bulk'
    and exists (select 1 from better_supabase.blocks where name = 'bulk-actions');

-- time-entries
delete from better_supabase.blocks
  where name = 'time-tracking'
    and exists (select 1 from better_supabase.blocks where name = 'time-entries');
