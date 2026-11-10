-- The bounded memo helpers every module shares (ADR 0644).
CREATE OR REPLACE FUNCTION better_supabase.memo_slot_get (
  key text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select case when pg_catalog.split_part(v.slot, pg_catalog.chr(31), 1) = key
    then nullif(pg_catalog.substr(v.slot, pg_catalog.length(key) + 2), '') end
  from (select pg_catalog.current_setting('better_supabase.memo.s' || (pg_catalog.hashtext(key) & 255)::text, true) as slot) v
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_slot_set (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select pg_catalog.set_config('better_supabase.memo.s' || (pg_catalog.hashtext(key) & 255)::text, key || pg_catalog.chr(31) || coalesce(value, ''), true)
$function$;
