import {
  DEADLINE_ADJUSTMENTS,
  OFFSET_LIMIT,
  OFFSET_UNITS,
} from "./deadlines-values.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/**
 * The pure SQL functions of the deadlines module: the rule evaluator and the
 * rule validator. They mirror `evaluateDeadlineRule` and
 * `validateDeadlineRules` in `deadlines-values.ts`.
 */
export function evaluatorSql(
  fn: (name: string) => string,
  grant: (signature: string) => string,
): string {
  return `
-- Evaluates one rule against facts: { status: 'due', dueOn } or
-- { status: 'unknown', missing: [fact names] }. The anchor fact is a date
-- (YYYY-MM-DD). Weekends are Saturday and Sunday; holidays are not modeled.
create or replace function ${fn("evaluate_deadline_rule")}(rule jsonb, facts jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_facts jsonb := coalesce(evaluate_deadline_rule.facts, '{}'::jsonb);
  v_name text;
  v_missing text[] := '{}';
  v_anchor date;
  v_due date;
  v_amount integer := (evaluate_deadline_rule.rule #>> '{offset,amount}')::integer;
  v_unit text := evaluate_deadline_rule.rule #>> '{offset,unit}';
  v_adjust text := coalesce(evaluate_deadline_rule.rule ->> 'adjust', 'none');
  v_step integer;
  v_left integer;
begin
  for v_name in
    select d.x from (
      select min(s.o) as o, s.x from (
        select 0 as o, evaluate_deadline_rule.rule ->> 'anchor' as x
        union all
        select e.ord::integer, e.v
        from jsonb_array_elements_text(coalesce(evaluate_deadline_rule.rule -> 'requires', '[]'::jsonb)) with ordinality as e(v, ord)
      ) s group by s.x
    ) d order by d.o
  loop
    if nullif(btrim(v_facts ->> v_name), '') is null then
      v_missing := v_missing || v_name;
    elsif v_name = evaluate_deadline_rule.rule ->> 'anchor' then
      begin
        if v_facts ->> v_name !~ '^\\s*\\d{4}-\\d{2}-\\d{2}\\s*$' then
          raise invalid_datetime_format;
        end if;
        v_anchor := btrim(v_facts ->> v_name)::date;
      exception when others then
        v_missing := v_missing || v_name;
      end;
    end if;
  end loop;
  if cardinality(v_missing) > 0 or v_anchor is null then
    return jsonb_build_object('status', 'unknown', 'missing', to_jsonb(v_missing));
  end if;
  v_due := v_anchor;
  if v_unit = 'days' then
    v_due := v_anchor + v_amount;
  elsif v_unit = 'months' then
    v_due := (v_anchor + make_interval(months => v_amount))::date;
  else
    v_step := case when v_amount < 0 then -1 else 1 end;
    v_left := abs(v_amount);
    while v_left > 0 loop
      v_due := v_due + v_step;
      while extract(isodow from v_due) in (6, 7) loop
        v_due := v_due + v_step;
      end loop;
      v_left := v_left - 1;
    end loop;
  end if;
  if v_adjust <> 'none' then
    v_step := case when v_adjust = 'next_business_day' then 1 else -1 end;
    while extract(isodow from v_due) in (6, 7) loop
      v_due := v_due + v_step;
    end loop;
  end if;
  return jsonb_build_object('status', 'due', 'dueOn', to_char(v_due, 'YYYY-MM-DD'));
end;
$$;
${grant(`${fn("evaluate_deadline_rule")}(jsonb, jsonb)`)}

-- The problems of a rule list, as text, empty when it is valid.
create or replace function ${fn("validate_deadline_rules")}(rules jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_issues text[] := '{}';
  v_rule jsonb;
  v_ord integer;
  v_key text;
  v_keys text[] := '{}';
  v_at text;
  v_name constant text := '^[a-z][a-z0-9_]{0,62}$';
  v_amount integer;
begin
  if validate_deadline_rules.rules is null or jsonb_typeof(validate_deadline_rules.rules) <> 'array' or jsonb_array_length(validate_deadline_rules.rules) = 0 then
    return array['a rule set version needs a non-empty list of rules'];
  end if;
  for v_rule, v_ord in
    select e.v, e.ord::integer from jsonb_array_elements(validate_deadline_rules.rules) with ordinality as e(v, ord)
  loop
    v_at := 'rule ' || v_ord;
    if jsonb_typeof(v_rule) <> 'object' then
      v_issues := v_issues || (v_at || ' must be an object');
      continue;
    end if;
    v_key := v_rule ->> 'key';
    if jsonb_typeof(v_rule -> 'key') is distinct from 'string' or v_key !~ v_name then
      v_issues := v_issues || (v_at || ' needs a key in lower case letters, digits and _');
    elsif v_key = any (v_keys) then
      v_issues := v_issues || (v_at || ' repeats the key ' || v_key);
    else
      v_keys := v_keys || v_key;
    end if;
    if jsonb_typeof(v_rule -> 'anchor') is distinct from 'string' or (v_rule ->> 'anchor') !~ v_name then
      v_issues := v_issues || (v_at || ' needs an anchor fact name');
    end if;
    v_amount := case when (v_rule #>> '{offset,amount}') ~ '^-?\\d{1,4}$' then (v_rule #>> '{offset,amount}')::integer end;
    if jsonb_typeof(v_rule -> 'offset') is distinct from 'object'
      or jsonb_typeof(v_rule #> '{offset,amount}') is distinct from 'number'
      or v_amount is null or abs(v_amount) > ${String(OFFSET_LIMIT)}
      or (v_rule #>> '{offset,unit}') is null or not (v_rule #>> '{offset,unit}') in (${list(OFFSET_UNITS)}) then
      v_issues := v_issues || (v_at || ' needs an offset of a whole amount up to ${String(OFFSET_LIMIT)} in ${OFFSET_UNITS.join(", ")}');
    end if;
    if v_rule ? 'adjust' and (jsonb_typeof(v_rule -> 'adjust') is distinct from 'string' or not (v_rule ->> 'adjust') in (${list(DEADLINE_ADJUSTMENTS)})) then
      v_issues := v_issues || (v_at || ' adjust is ${DEADLINE_ADJUSTMENTS.join(", ")}');
    end if;
    if v_rule ? 'requires' and (
      jsonb_typeof(v_rule -> 'requires') is distinct from 'array'
      or exists (
        select 1 from jsonb_array_elements(v_rule -> 'requires') r
        where jsonb_typeof(r) <> 'string' or (r #>> '{}') !~ v_name
      )
    ) then
      v_issues := v_issues || (v_at || ' requires is a list of fact names');
    end if;
    if jsonb_typeof(v_rule -> 'citation') is distinct from 'object'
      or jsonb_typeof(v_rule #> '{citation,reference}') is distinct from 'string'
      or btrim(v_rule #>> '{citation,reference}') = '' then
      v_issues := v_issues || (v_at || ' needs a citation with a reference');
    end if;
  end loop;
  return v_issues;
end;
$$;
${grant(`${fn("validate_deadline_rules")}(jsonb)`)}
`;
}
