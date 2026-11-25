SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.format_assigned_number (
  template text,
  n        bigint,
  at       timestamp with time zone
)
  RETURNS text
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v text := template;
  width text[];
begin
  v := replace(v, '{yyyy}', to_char(at at time zone 'utc', 'YYYY'));
  v := replace(v, '{yy}', to_char(at at time zone 'utc', 'YY'));
  v := replace(v, '{mm}', to_char(at at time zone 'utc', 'MM'));
  v := replace(v, '{dd}', to_char(at at time zone 'utc', 'DD'));
  while v ~ '\{n:[0-9]+\}' loop
    width := regexp_match(v, '\{n:([0-9]+)\}');
    v := regexp_replace(v, '\{n:[0-9]+\}', lpad(n::text, greatest(width[1]::int, length(n::text)), '0'));
  end loop;
  return replace(v, '{n}', n::text);
end;
$function$;
