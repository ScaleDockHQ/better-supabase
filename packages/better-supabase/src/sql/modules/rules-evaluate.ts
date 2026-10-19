import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { FILTER_OPERATORS, NEGATIVE } from "../../list/filter-query.ts";

/** `{ type: { operator: arity } }`, from the list tooling's operator table. */
export function operatorTable(): string {
  const table = Object.fromEntries(
    Object.entries(FILTER_OPERATORS).map(([type, operators]) => [
      type,
      Object.fromEntries(operators.map((entry) => [entry.value, entry.arity])),
    ]),
  );

  return `${sqlString(JSON.stringify(table))}::jsonb`;
}

function negativeCase(operator: string): string {
  const arms = Object.entries(NEGATIVE)
    .map(
      ([negative, base]) =>
        `when ${sqlString(negative)} then ${sqlString(base)}`,
    )
    .join(" ");

  return `case ${operator} ${arms} end`;
}

/** The pure evaluator: the same operators and null handling as `evaluateFilterQuery`. */
export function rulesEvaluator(ctx: ModuleContext): string {
  const fn = (name: string): string => ctx.fn(name);

  return `-- A JSON value as text the way the TypeScript evaluator reads it:
-- strings as they are, numbers and booleans printed, anything else null.
create or replace function ${fn("rule_text")}(value jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case jsonb_typeof(value)
    when 'string' then value #>> '{}'
    when 'number' then value::text
    when 'boolean' then value::text
  end
$$;

create or replace function ${fn("rule_numeric")}(value jsonb)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
begin
  if jsonb_typeof(value) = 'number' then
    return (value #>> '{}')::numeric;
  end if;
  if jsonb_typeof(value) is distinct from 'string' then
    return null;
  end if;
  v_text := trim(value #>> '{}');
  if v_text = '' or lower(v_text) in ('nan', 'infinity', '+infinity', '-infinity', 'inf', '+inf', '-inf') then
    return null;
  end if;
  return v_text::numeric;
exception when others then
  return null;
end;
$$;

create or replace function ${fn("rule_boolean")}(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(value) = 'boolean' then (value #>> '{}')::boolean
    when value = '"true"'::jsonb then true
    when value = '"false"'::jsonb then false
  end
$$;

-- An array value, or a string holding a JSON array, as text elements.
create or replace function ${fn("rule_list")}(value jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_array jsonb := value;
begin
  if jsonb_typeof(value) = 'string' and left(value #>> '{}', 1) = '[' then
    v_array := (value #>> '{}')::jsonb;
  end if;
  if jsonb_typeof(v_array) is distinct from 'array' then
    return null;
  end if;
  return coalesce((
    select array_agg(case jsonb_typeof(e.value) when 'string' then e.value #>> '{}' else e.value::text end order by e.n)
    from jsonb_array_elements(v_array) with ordinality e(value, n)
  ), '{}');
exception when others then
  return null;
end;
$$;

-- A date value as a timestamp in the column's own ordering: the UTC instant
-- for timestamptz, the day for date and the wall clock for timestamp.
create or replace function ${fn("rule_moment")}(kind text, value jsonb)
returns timestamp
language plpgsql
stable
set search_path = ''
as $$
declare
  v_text text;
begin
  if jsonb_typeof(value) is distinct from 'string' then
    return null;
  end if;
  v_text := value #>> '{}';
  if kind = 'timestamptz' then
    return v_text::timestamptz at time zone 'UTC';
  end if;
  if kind = 'date' then
    return left(v_text, 10)::date::timestamp;
  end if;
  return v_text::timestamp;
exception when others then
  return null;
end;
$$;

-- The [start, end) bounds of a date value ({ date, time, relative }) in the
-- same ordering as rule_moment, the way dateBounds resolves them.
create or replace function ${fn("rule_bounds")}(kind text, value jsonb, time_zone text, now timestamptz)
returns timestamp[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_day date;
  v_offset integer;
  v_time time;
  v_from timestamp;
  v_to timestamp;
begin
  if jsonb_typeof(value -> 'relative') = 'object' then
    v_day := (rule_bounds.now at time zone rule_bounds.time_zone)::date;
    v_offset := coalesce((value -> 'relative' ->> 'offset')::integer, 0);
    v_day := (v_day + case value -> 'relative' ->> 'unit'
      when 'day' then make_interval(days => v_offset)
      when 'week' then make_interval(weeks => v_offset)
      when 'month' then make_interval(months => v_offset)
      else make_interval(years => v_offset)
    end)::date;
  else
    v_day := (value ->> 'date')::date;
  end if;
  if kind = 'date' then
    return array[v_day::timestamp, (v_day + 1)::timestamp];
  end if;
  v_time := (value ->> 'time')::time;
  v_from := v_day + coalesce(v_time, time '00:00');
  v_to := case when v_time is null then v_from + interval '1 day' else v_from + interval '1 minute' end;
  if kind = 'timestamp' then
    return array[v_from, v_to];
  end if;
  return array[
    (v_from at time zone rule_bounds.time_zone) at time zone 'UTC',
    (v_to at time zone rule_bounds.time_zone) at time zone 'UTC'
  ];
end;
$$;

create or replace function ${fn("rule_date")}(kind text, operator text, operand jsonb, value jsonb, time_zone text, now timestamptz)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_at timestamp := ${fn("rule_moment")}(kind, value);
  v_bounds timestamp[];
begin
  if v_at is null then
    return null;
  end if;
  if operator = 'between' then
    return v_at >= (${fn("rule_bounds")}(kind, operand -> 0, time_zone, now))[1]
      and v_at < (${fn("rule_bounds")}(kind, operand -> 1, time_zone, now))[2];
  end if;
  v_bounds := ${fn("rule_bounds")}(kind, operand, time_zone, now);
  case operator
    when 'is' then return v_at >= v_bounds[1] and v_at < v_bounds[2];
    when 'is_before' then return v_at < v_bounds[1];
    when 'is_after' then return v_at >= v_bounds[2];
    when 'is_on_or_before' then return v_at < v_bounds[2];
    when 'is_on_or_after' then return v_at >= v_bounds[1];
  end case;
end;
$$;

create or replace function ${fn("rule_equal")}(type text, operand jsonb, value jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_boolean boolean;
  v_number numeric;
  v_text text;
begin
  if value is null then
    return null;
  end if;
  if type = 'boolean' then
    v_boolean := ${fn("rule_boolean")}(value);
    return case when v_boolean is null then null else v_boolean = coalesce(operand in ('true'::jsonb, '"true"'::jsonb), false) end;
  end if;
  if type = 'number' then
    v_number := ${fn("rule_numeric")}(value);
    return case when v_number is null then null else coalesce(v_number = ${fn("rule_numeric")}(operand), false) end;
  end if;
  v_text := ${fn("rule_text")}(value);
  return case when v_text is null then null else coalesce(v_text = ${fn("rule_text")}(operand), false) end;
end;
$$;

-- The truth of a positive operator (negations are handled by rule_node).
create or replace function ${fn("rule_positive")}(type text, kind text, operator text, operand jsonb, value jsonb, time_zone text, now timestamptz)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_text text := ${fn("rule_text")}(value);
  v_needle text;
  v_value numeric;
  v_low numeric;
  v_high numeric;
  v_list text[];
begin
  case operator
    when 'empty' then
      return value is null or (type = 'text' and value = '""'::jsonb);
    when 'contains', 'starts_with', 'ends_with' then
      if v_text is null then
        return null;
      end if;
      v_needle := lower(coalesce(operand #>> '{}', ''));
      return case operator
        when 'contains' then strpos(lower(v_text), v_needle) > 0
        when 'starts_with' then left(lower(v_text), length(v_needle)) = v_needle
        else right(lower(v_text), length(v_needle)) = v_needle
      end;
    when 'eq' then
      return ${fn("rule_equal")}(type, operand, value);
    when 'gt', 'gte', 'lt', 'lte' then
      v_value := ${fn("rule_numeric")}(value);
      v_low := ${fn("rule_numeric")}(operand);
      if v_value is null or v_low is null then
        return null;
      end if;
      return case operator
        when 'gt' then v_value > v_low
        when 'gte' then v_value >= v_low
        when 'lt' then v_value < v_low
        else v_value <= v_low
      end;
    when 'is_any_of' then
      if value is null then
        return null;
      end if;
      return v_text is not null and jsonb_typeof(operand) = 'array'
        and exists (select 1 from jsonb_array_elements(operand) e where ${fn("rule_text")}(e.value) = v_text);
    when 'has_any_of', 'has_all_of' then
      v_list := ${fn("rule_list")}(value);
      if v_list is null or jsonb_typeof(operand) is distinct from 'array' then
        return null;
      end if;
      if operator = 'has_any_of' then
        return exists (select 1 from unnest(${fn("rule_list")}(operand)) w where w = any (v_list));
      end if;
      return not exists (select 1 from unnest(${fn("rule_list")}(operand)) w where not (w = any (v_list)));
    when 'is' then
      if type = 'date' then
        return ${fn("rule_date")}(kind, operator, operand, value, time_zone, now);
      end if;
      return ${fn("rule_equal")}(type, operand, value);
    when 'between' then
      if type = 'date' then
        return ${fn("rule_date")}(kind, operator, operand, value, time_zone, now);
      end if;
      v_value := ${fn("rule_numeric")}(value);
      v_low := least(${fn("rule_numeric")}(operand -> 0), ${fn("rule_numeric")}(operand -> 1));
      v_high := greatest(${fn("rule_numeric")}(operand -> 0), ${fn("rule_numeric")}(operand -> 1));
      if v_value is null or v_low is null or v_high is null then
        return null;
      end if;
      return v_value >= v_low and v_value <= v_high;
    else
      return ${fn("rule_date")}(kind, operator, operand, value, time_zone, now);
  end case;
end;
$$;

-- One node of a tree: { truth, results } by node id, or null when the node
-- takes no part (an unfinished rule, an unknown field, an empty group).
create or replace function ${fn("rule_node")}(node jsonb, subject jsonb, fields jsonb, time_zone text, now timestamptz)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_field jsonb;
  v_value jsonb;
  v_operator text := coalesce(node ->> 'operator', '');
  v_base text;
  v_negative boolean;
  v_truth boolean;
  v_part jsonb;
  v_parts boolean[] := '{}';
  v_results jsonb := '{}'::jsonb;
begin
  if node ->> 'type' = 'rule' then
    v_field := fields -> (
      select string_agg(p.value, '.' order by p.n)
      from jsonb_array_elements_text(coalesce(node -> 'path', '[]'::jsonb)) with ordinality p(value, n)
    );
    if v_operator = '' or v_field is null then
      return null;
    end if;
    v_value := subject #> string_to_array(v_field ->> 'column', '.');
    if jsonb_typeof(v_value) = 'null' then
      v_value := null;
    end if;
    v_base := ${negativeCase("v_operator")};
    v_negative := (v_base is not null) <> coalesce((node ->> 'negated')::boolean, false);
    v_operator := coalesce(v_base, v_operator);
    v_truth := ${fn("rule_positive")}(v_field ->> 'type', coalesce(v_field ->> 'columnType', 'text'), v_operator, node -> 'value', v_value, time_zone, now);
    if v_negative then
      -- "is not x" also matches records without a value, except for "is not empty".
      if coalesce((v_field ->> 'nullable')::boolean, true) and v_operator <> 'empty' and v_value is null then
        v_truth := true;
      else
        v_truth := not v_truth;
      end if;
    end if;
    return jsonb_build_object('truth', v_truth, 'results', jsonb_build_object(node ->> 'id', v_truth));
  end if;
  for v_part in
    select ${fn("rule_node")}(e.value, subject, fields, time_zone, now)
    from jsonb_array_elements(coalesce(node -> 'rules', '[]'::jsonb)) with ordinality e(value, n)
    order by e.n
  loop
    if v_part is not null then
      v_parts := v_parts || (v_part ->> 'truth')::boolean;
      v_results := v_results || (v_part -> 'results');
    end if;
  end loop;
  if cardinality(v_parts) = 0 then
    return null;
  end if;
  if node ->> 'combinator' = 'and' then
    v_truth := not (false = any (v_parts));
  else
    v_truth := true = any (v_parts);
  end if;
  return jsonb_build_object('truth', v_truth, 'results', v_results || jsonb_build_object(node ->> 'id', v_truth));
end;
$$;

-- A filter tree on one subject: { matched, results }, the same answer as
-- evaluateFilterQuery. fields maps a field id to { type, column,
-- columnType, nullable }, as rule_field_map returns it.
create or replace function ${fn("rule_evaluate")}(conditions jsonb, subject jsonb, fields jsonb, time_zone text default 'UTC', now timestamptz default now())
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_node jsonb := ${fn("rule_node")}(conditions, subject, fields, time_zone, now);
begin
  return jsonb_build_object(
    'matched', v_node is null or coalesce((v_node ->> 'truth')::boolean, false),
    'results', coalesce(v_node -> 'results', '{}'::jsonb)
  );
end;
$$;

create or replace function ${fn("rule_matches")}(conditions jsonb, subject jsonb, fields jsonb, time_zone text default 'UTC', now timestamptz default now())
returns boolean
language sql
stable
set search_path = ''
as $$
  select (${fn("rule_evaluate")}(conditions, subject, fields, time_zone, now) ->> 'matched')::boolean
$$;`;
}
