set lock_timeout = '5s';

create or replace function "better_supabase"."maintenance_next_occurrence"(dtstart timestamptz, tz text, rrule text, after timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select min(s) from better_supabase.rrule_occurrences(
    maintenance_next_occurrence.rrule, maintenance_next_occurrence.dtstart, maintenance_next_occurrence.tz,
    tstzrange(maintenance_next_occurrence.after + interval '1 microsecond', maintenance_next_occurrence.after + interval '10 years', '[)')) s;
$$;

drop function if exists "api"."maintenance_rule_starts"(timestamptz, text, text, timestamptz, timestamptz);
drop function if exists "better_supabase"."maintenance_rule_starts"(timestamptz, text, text, timestamptz, timestamptz);
