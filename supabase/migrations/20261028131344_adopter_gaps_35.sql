SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_held (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."drive_nodes" h
    where (h."id" in (select s.node_id from "better_supabase"."drive_subtree"(drive_node_held.node) s)
        or h."id" = any ("better_supabase"."drive_ancestors"(drive_node_held.node)))
      and h."legal_hold_until" is not null and h."legal_hold_until" > now()
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.time_entry_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- Only a change to logged time (options.lockedColumns) touches the week.
  if tg_op = 'UPDATE' and (new."started_at", new."ended_at", new."subject_type", new."subject_id", new."user_id", new."rate", new."rate_currency") is not distinct from (old."started_at", old."ended_at", old."subject_type", old."subject_id", old."user_id", old."rate", old."rate_currency") then
    return new;
  end if;
  if tg_op in ('UPDATE', 'DELETE') and "better_supabase"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "better_supabase"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;
