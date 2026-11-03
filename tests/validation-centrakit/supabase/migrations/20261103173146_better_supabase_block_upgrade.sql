-- better-supabase upgrade: steps that run before the schema diff.

-- webhook-inbox: version 8 to 9. fail_webhook takes permanent, which marks the message dead without further attempts.
drop function if exists better_supabase.fail_webhook(bigint, text, text, interval, integer);
