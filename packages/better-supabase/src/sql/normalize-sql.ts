/**
 * The SQL twins of `normalizePhone` and `validateIban`, so a target that writes
 * in the database can call them. The rules match the TypeScript helpers.
 */
export const NORMALIZE_SQL = `
create or replace function better_supabase.validate_iban(value text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  compact text;
  moved text;
  rest integer := 0;
  i integer;
  piece text;
  j integer;
begin
  compact := upper(regexp_replace(coalesce(value, ''), '\\s', '', 'g'));
  if compact !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then
    return false;
  end if;
  moved := substring(compact from 5) || substring(compact from 1 for 4);
  for i in 1 .. char_length(moved) loop
    piece := case
      when substring(moved from i for 1) between 'A' and 'Z'
        then (ascii(substring(moved from i for 1)) - 55)::text
      else substring(moved from i for 1)
    end;
    for j in 1 .. char_length(piece) loop
      rest := (rest * 10 + ascii(substring(piece from j for 1)) - 48) % 97;
    end loop;
  end loop;
  return rest = 1;
end;
$$;
revoke execute on function better_supabase.validate_iban(text) from public, anon;
grant execute on function better_supabase.validate_iban(text) to authenticated, service_role;

create or replace function better_supabase.normalize_phone(value text, region text default null)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when compact like '00%' then '+' || regexp_replace(substring(compact from 3), '\\D', '', 'g')
    when compact like '+%' then '+' || regexp_replace(substring(compact from 2), '\\D', '', 'g')
    when upper(region) = 'NL' and digits like '0%' then '+31' || substring(digits from 2)
    when upper(region) = 'DE' and digits like '0%' then '+49' || substring(digits from 2)
    when upper(region) = 'FR' and digits like '0%' then '+33' || substring(digits from 2)
    when upper(region) = 'GB' and digits like '0%' then '+44' || substring(digits from 2)
    when upper(region) = 'US' then '+1' || digits
    else digits
  end
  from (
    select regexp_replace(coalesce(value, ''), '[\\s().-]', '', 'g') as compact
  ) raw,
  lateral (
    select case when compact like '00%' then substring(compact from 3) else compact end as body
  ) body,
  lateral (
    select regexp_replace(body, '\\D', '', 'g') as digits
  ) digits
$$;
revoke execute on function better_supabase.normalize_phone(text, text) from public, anon;
grant execute on function better_supabase.normalize_phone(text, text) to authenticated, service_role;
`;
