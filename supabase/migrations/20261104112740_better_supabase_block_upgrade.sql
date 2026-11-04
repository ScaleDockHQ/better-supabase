-- better-supabase upgrade: steps that run before the schema diff.

-- queue: version 10 to 11. ready_job_queues answers which queues have a claimable message, and list_schedules returns each schedule's payload.
drop function if exists better_supabase.list_schedules(text, text);
