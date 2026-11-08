-- The built-in goal metric of the tasks block is tasks.completed, the block's
-- permission-key name, not the work_items table name. Data only.
update "better_supabase"."goals" set "metric" = 'tasks.completed' where "metric" = 'work_items.completed';
