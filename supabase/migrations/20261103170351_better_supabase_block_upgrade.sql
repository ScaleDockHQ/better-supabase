-- better-supabase upgrade: steps that run before the schema diff.

-- inbox: version 9 to 10. record_inbound runs as its owner, so the service role can call it: the functions it uses stay closed to API roles.
alter function "better_supabase"."record_inbound"(jsonb) security definer;
