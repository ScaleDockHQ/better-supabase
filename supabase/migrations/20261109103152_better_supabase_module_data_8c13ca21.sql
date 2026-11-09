-- better-supabase add --adopt: the rows and settings of bulk-actions, time-entries that no data migration holds yet.

set lock_timeout = '5s';

-- bulk-actions
update better_supabase.blocks set name = 'bulk-actions'
  where name = 'bulk'
    and not exists (select 1 from better_supabase.blocks where name = 'bulk-actions');

-- time-entries
update better_supabase.blocks set name = 'time-entries'
  where name = 'time-tracking'
    and not exists (select 1 from better_supabase.blocks where name = 'time-entries');
