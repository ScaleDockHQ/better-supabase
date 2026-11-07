import {
  FIRST_FURNISHING_FACT,
  LAST_FURNISHING_FACT,
  OFFSET_LIMIT,
  WEEKDAYS,
} from "./deadlines-values.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/**
 * The SQL evaluator of the deadlines module, `evaluate_deadlines`, and its
 * helpers. Each mirrors the function of the same concept in
 * `deadlines-evaluate.ts` (`evaluateVersion`, `deadlineIsHoliday`,
 * `deadlineAdd`); the golden fixtures run both. The helpers are not callable
 * through the API.
 */
export function evaluatorSql(
  fn: (name: string) => string,
  grant: (signature: string) => string,
  helperGrant: (signature: string) => string,
): string {
  const date = fn("deadline_date");
  const holidaysOf = fn("deadline_holidays_of");
  const isHoliday = fn("deadline_is_holiday");
  const businessDay = fn("deadline_business_day");
  const add = fn("deadline_add");
  const roll = fn("deadline_roll");
  const candidate = fn("deadline_candidate");
  const outcome = fn("deadline_outcome");
  const periods = fn("deadline_periods");
  const judge = fn("deadline_judge");
  const select = fn("deadline_select_rule");
  const group = fn("deadline_group");
  const cascade = fn("deadline_cascade");
  const sortedText = fn("deadline_sorted");
  const whole = fn("deadline_whole");

  return `
-- An ISO date (YYYY-MM-DD) held in a jsonb string, or null.
create or replace function ${date}(value jsonb)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text := value #>> '{}';
begin
  if jsonb_typeof(value) is distinct from 'string' or v_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    return null;
  end if;
  return make_date(substr(v_text, 1, 4)::integer, substr(v_text, 6, 2)::integer, substr(v_text, 9, 2)::integer);
exception when others then
  return null;
end;
$$;
${helperGrant(`${date}(jsonb)`)}

-- Distinct text values in byte order, as a jsonb array.
create or replace function ${sortedText}(names text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(s.x order by s.x collate "C"), '[]'::jsonb)
  from (select distinct u.x from unnest(names) u(x) where u.x is not null) s
$$;
${helperGrant(`${sortedText}(text[])`)}

-- A whole number from min to max held in jsonb.
create or replace function ${whole}(value jsonb, min_value integer, max_value integer)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) is not distinct from 'number'
    and (value #>> '{}')::numeric % 1 = 0
    and (value #>> '{}')::numeric between min_value and max_value
$$;
${helperGrant(`${whole}(jsonb, integer, integer)`)}

-- The days a counting block's holidays fall on for the dates listed in a year.
create or replace function ${holidaysOf}(holidays jsonb, year integer)
returns date[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_holiday jsonb;
  v_observed jsonb;
  v_month integer;
  v_first date;
  v_last integer;
  v_listed date;
  v_wanted integer;
  v_dow integer;
  v_target integer;
  v_moved date[];
  v_replaces boolean;
  v_days date[] := '{}';
begin
  for v_holiday in select e.value from jsonb_array_elements(coalesce(holidays, '[]'::jsonb)) e(value) loop
    v_month := (v_holiday #>> '{date,month}')::integer;
    v_first := make_date(year, v_month, 1);
    v_last := (v_first + interval '1 month')::date - v_first;
    if v_holiday -> 'date' ? 'day' then
      if (v_holiday #>> '{date,day}')::integer > v_last then
        continue;
      end if;
      v_listed := make_date(year, v_month, (v_holiday #>> '{date,day}')::integer);
    else
      v_wanted := array_position(array[${list(WEEKDAYS)}], v_holiday #>> '{date,weekday}');
      if v_holiday #>> '{date,nth}' = 'last' then
        v_listed := v_first + (v_last - 1);
        v_listed := v_listed - ((extract(isodow from v_listed)::integer - v_wanted + 7) % 7);
      else
        v_listed := v_first + ((v_wanted - extract(isodow from v_first)::integer + 7) % 7) + ((v_holiday #>> '{date,nth}')::integer - 1) * 7;
        if v_listed - v_first >= v_last then
          continue;
        end if;
      end if;
    end if;
    v_moved := '{}';
    v_replaces := false;
    v_dow := extract(isodow from v_listed)::integer;
    for v_observed in select e.value from jsonb_array_elements(coalesce(v_holiday -> 'observed', '[]'::jsonb)) e(value) loop
      if (v_observed ->> 'falls_on' = 'saturday' and v_dow = 6)
        or (v_observed ->> 'falls_on' = 'sunday' and v_dow = 7)
        or (v_observed ->> 'falls_on' = 'other_than_sunday' and v_dow <> 7) then
        v_target := case v_observed ->> 'observe' when 'preceding_friday' then 5 when 'following_monday' then 1 else 7 end;
        if v_observed ->> 'observe' in ('preceding_friday', 'preceding_sunday') then
          v_moved := v_moved || (v_listed - (((v_dow - v_target + 6) % 7) + 1));
        else
          v_moved := v_moved || (v_listed + (((v_target - v_dow + 6) % 7) + 1));
        end if;
        if v_observed -> 'replaces' = 'true'::jsonb then
          v_replaces := true;
        end if;
      end if;
    end loop;
    v_days := v_days || case when v_replaces then v_moved else array[v_listed] || v_moved end;
  end loop;
  return v_days;
end;
$$;
${helperGrant(`${holidaysOf}(jsonb, integer)`)}

-- Whether a day is a holiday of a counting block: listed in its year, or
-- observed from a date listed in the year before or after.
create or replace function ${isHoliday}(counting jsonb, day date)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_holidays jsonb := case when jsonb_typeof(counting) = 'object' then counting -> 'holidays' end;
  v_year integer := extract(year from day)::integer;
begin
  if jsonb_typeof(v_holidays) is distinct from 'array' or jsonb_array_length(v_holidays) = 0 then
    return false;
  end if;
  return day = any (${holidaysOf}(v_holidays, v_year - 1) || ${holidaysOf}(v_holidays, v_year) || ${holidaysOf}(v_holidays, v_year + 1));
end;
$$;
${helperGrant(`${isHoliday}(jsonb, date)`)}

-- Not a weekend, and not a holiday of an approved counting block.
create or replace function ${businessDay}(counting jsonb, day date)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select extract(isodow from day) < 6
    and not (jsonb_typeof(counting) is not distinct from 'object'
      and coalesce(counting ->> 'status', 'approved') = 'approved'
      and ${isHoliday}(counting, day))
$$;
${helperGrant(`${businessDay}(jsonb, date)`)}

-- The date a count yields from an anchor date, before any roll.
create or replace function ${add}(anchor date, count jsonb, counting jsonb default null)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_n integer := coalesce((count ->> 'n')::integer, 0) * case when count ->> 'before' is null then 1 else -1 end;
  v_day date := anchor;
  v_first date;
  v_step integer;
  v_left integer;
begin
  if anchor is null then
    return null;
  end if;
  if count ->> 'unit' = 'months' then
    if count ->> 'day_of_month' is null then
      return (anchor + make_interval(months => v_n))::date;
    end if;
    v_first := (date_trunc('month', anchor)::date + make_interval(months => v_n))::date;
    return make_date(extract(year from v_first)::integer, extract(month from v_first)::integer,
      least((count ->> 'day_of_month')::integer, (v_first + interval '1 month')::date - v_first));
  end if;
  if count ->> 'unit' = 'business_days' then
    v_step := case when v_n < 0 then -1 else 1 end;
    v_left := abs(v_n);
    if v_left > ${String(OFFSET_LIMIT)} then
      raise exception 'n is a whole number from 0 to ${String(OFFSET_LIMIT)}' using errcode = '22023', hint = 'DEADLINE_INVALID';
    end if;
    while v_left > 0 loop
      v_day := v_day + v_step;
      if ${businessDay}(counting, v_day) then
        v_left := v_left - 1;
      end if;
    end loop;
    return v_day;
  end if;
  return anchor + v_n;
end;
$$;
${helperGrant(`${add}(date, jsonb, jsonb)`)}

-- A last day rolled past the days an approved counting block names (when the
-- deadline rolls), then moved off a non-business day by the rule's adjust.
create or replace function ${roll}(counting jsonb, day date, rolls boolean, adjust text)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_day date := day;
  v_when jsonb := counting -> 'roll_when';
  v_step integer;
begin
  if rolls and jsonb_typeof(counting) is not distinct from 'object' and coalesce(counting ->> 'status', 'approved') = 'approved' then
    while (v_when ? 'saturday' and extract(isodow from v_day) = 6)
      or (v_when ? 'sunday' and extract(isodow from v_day) = 7)
      or (v_when ? 'holiday' and ${isHoliday}(counting, v_day)) loop
      v_day := v_day + 1;
    end loop;
  end if;
  if coalesce(adjust, 'none') <> 'none' then
    v_step := case when adjust = 'next_business_day' then 1 else -1 end;
    while not ${businessDay}(counting, v_day) loop
      v_day := v_day + v_step;
    end loop;
  end if;
  return v_day;
end;
$$;
${helperGrant(`${roll}(jsonb, date, boolean, text)`)}

-- One count against the facts: { state: dated, due, fact, anchor } when its
-- fact holds a date, { state: skipped } when the fact is null, and
-- { state: unanswered, asks } otherwise.
create or replace function ${candidate}(count jsonb, facts jsonb, counting jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_fact text := coalesce(count ->> 'from', count ->> 'before', '');
  v_anchor date;
begin
  if not facts ? v_fact then
    return jsonb_build_object('state', 'unanswered', 'asks', jsonb_build_array(v_fact));
  end if;
  if facts -> v_fact = 'null'::jsonb then
    return jsonb_build_object('state', 'skipped');
  end if;
  v_anchor := ${date}(facts -> v_fact);
  if v_anchor is null then
    return jsonb_build_object('state', 'unanswered', 'asks', jsonb_build_array(v_fact));
  end if;
  return jsonb_build_object('state', 'dated', 'due', ${add}(v_anchor, count, counting), 'fact', v_fact, 'anchor', v_anchor);
end;
$$;
${helperGrant(`${candidate}(jsonb, jsonb, jsonb)`)}

-- A rule's deadline against the facts, before any roll: { result: due |
-- unknown | pending | undated, due, asks, basis }.
create or replace function ${outcome}(deadline jsonb, facts jsonb, counting jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_kind text;
  v_counts jsonb;
  v_candidates jsonb[] := '{}';
  v_count jsonb;
  v_candidate jsonb;
  v_asks text[] := '{}';
  v_before text[] := '{}';
  v_without text[] := '{}';
  v_dated date[] := '{}';
  v_taken jsonb;
  v_undated jsonb;
begin
  if deadline is null or jsonb_typeof(deadline) = 'null' or deadline = '"none"'::jsonb then
    return jsonb_build_object('result', 'undated', 'due', null, 'asks', '[]'::jsonb, 'basis', null);
  end if;
  v_kind := case when deadline ? 'first_of' then 'first_of' when deadline ? 'earlier_of' then 'earlier_of' when deadline ? 'later_of' then 'later_of' else 'count' end;
  v_counts := case when v_kind = 'count' then jsonb_build_array(deadline) else deadline -> v_kind end;
  for v_count in select e.value from jsonb_array_elements(v_counts) e(value) loop
    v_candidate := ${candidate}(v_count, facts, counting);
    v_candidates := v_candidates || v_candidate;
    if v_candidate ->> 'state' = 'unanswered' then
      v_asks := v_asks || array(select jsonb_array_elements_text(v_candidate -> 'asks'));
      if v_taken is null then
        v_before := v_before || array(select jsonb_array_elements_text(v_candidate -> 'asks'));
      end if;
    elsif v_candidate ->> 'state' = 'skipped' then
      if v_count ->> 'from' is not null then
        v_without := v_without || (v_count ->> 'from');
      end if;
    else
      v_dated := v_dated || (v_candidate ->> 'due')::date;
      if v_taken is null then
        v_taken := v_candidate;
      end if;
    end if;
  end loop;
  v_undated := jsonb_build_object('result', case when cardinality(v_asks) > 0 then 'unknown' else 'pending' end,
    'due', null, 'asks', to_jsonb(v_asks), 'basis', null);
  if v_kind = 'first_of' then
    if v_taken is null then
      return v_undated;
    end if;
    return jsonb_build_object('result', 'due', 'due', v_taken -> 'due', 'asks', to_jsonb(v_before),
      'basis', jsonb_build_object('anchor', jsonb_build_object('fact', v_taken -> 'fact', 'date', v_taken -> 'anchor'), 'without', to_jsonb(v_without)));
  end if;
  if v_kind = 'earlier_of' then
    if cardinality(v_dated) = 0 then
      return v_undated;
    end if;
    return jsonb_build_object('result', 'due', 'due', (select min(x) from unnest(v_dated) x), 'asks', to_jsonb(v_asks),
      'basis', jsonb_build_object('anchor', null, 'without', to_jsonb(v_without)));
  end if;
  if v_kind = 'later_of' then
    if cardinality(v_dated) = 0 or cardinality(v_asks) > 0 then
      return v_undated;
    end if;
    return jsonb_build_object('result', 'due', 'due', (select max(x) from unnest(v_dated) x), 'asks', '[]'::jsonb,
      'basis', jsonb_build_object('anchor', null, 'without', '[]'::jsonb));
  end if;
  if v_taken is null then
    return v_undated;
  end if;
  return jsonb_build_object('result', 'due', 'due', v_taken -> 'due', 'asks', '[]'::jsonb,
    'basis', jsonb_build_object('anchor', jsonb_build_object('fact', v_taken -> 'fact', 'date', v_taken -> 'anchor'), 'without', '[]'::jsonb));
end;
$$;
${helperGrant(`${outcome}(jsonb, jsonb, jsonb)`)}

-- A monthly count's months as their first days, or what it waits for: from
-- the first furnishing month through the last, or while furnishing goes on
-- through the month of as_of and one ahead.
create or replace function ${periods}(facts jsonb, as_of date)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_first date;
  v_last date;
  v_ongoing boolean;
  v_end date;
  v_month date;
  v_months date[] := '{}';
begin
  if facts -> '${FIRST_FURNISHING_FACT}' = 'null'::jsonb then
    return jsonb_build_object('months', '[]'::jsonb, 'asks', '[]'::jsonb);
  end if;
  v_first := ${date}(facts -> '${FIRST_FURNISHING_FACT}');
  if v_first is null then
    return jsonb_build_object('months', '[]'::jsonb, 'asks', jsonb_build_array('${FIRST_FURNISHING_FACT}'));
  end if;
  v_last := ${date}(facts -> '${LAST_FURNISHING_FACT}');
  v_ongoing := v_last is null or v_last > as_of;
  v_end := date_trunc('month', case when v_ongoing then as_of else v_last end)::date;
  v_month := date_trunc('month', v_first)::date;
  loop
    v_months := v_months || v_month;
    v_month := (v_month + interval '1 month')::date;
    exit when v_month > v_end;
  end loop;
  if v_ongoing then
    v_months := v_months || v_month;
  end if;
  return jsonb_build_object('months', to_jsonb(v_months), 'asks', '[]'::jsonb);
end;
$$;
${helperGrant(`${periods}(jsonb, date)`)}

-- A three-valued AND of a condition's entries: { verdict: true | false |
-- unknown, asks }. A missing fact is unknown; null is absent for present and
-- absent, and unknown otherwise.
create or replace function ${judge}(condition jsonb, facts jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_fact text;
  v_expected jsonb;
  v_value jsonb;
  v_code text;
  v_verdict text;
  v_asks text[] := '{}';
begin
  for v_fact, v_expected in select e.key, e.value from jsonb_each(coalesce(condition, '{}'::jsonb)) e loop
    if not facts ? v_fact then
      v_verdict := 'unknown';
    else
      v_value := facts -> v_fact;
      if v_expected in ('"present"'::jsonb, '"absent"'::jsonb) then
        v_verdict := case when (jsonb_typeof(v_value) <> 'null') = (v_expected = '"present"'::jsonb) then 'true' else 'false' end;
      elsif jsonb_typeof(v_value) = 'null' then
        v_verdict := 'unknown';
      elsif jsonb_typeof(v_expected) = 'boolean' then
        v_verdict := case when v_value = v_expected then 'true' else 'false' end;
      else
        v_code := case when jsonb_typeof(v_value) in ('string', 'number') then v_value #>> '{}' end;
        if jsonb_typeof(v_expected) = 'string' then
          v_verdict := case when v_code is not null and v_code = v_expected #>> '{}' then 'true' else 'false' end;
        else
          v_verdict := case when v_code is not null and v_code = any (array(select jsonb_array_elements_text(v_expected))) then 'true' else 'false' end;
        end if;
      end if;
    end if;
    if v_verdict = 'false' then
      return jsonb_build_object('verdict', 'false', 'asks', '[]'::jsonb);
    end if;
    if v_verdict = 'unknown' then
      v_asks := v_asks || v_fact;
    end if;
  end loop;
  return jsonb_build_object('verdict', case when cardinality(v_asks) > 0 then 'unknown' else 'true' end, 'asks', to_jsonb(v_asks));
end;
$$;
${helperGrant(`${judge}(jsonb, jsonb)`)}

-- The first rule of a group that applies, unless an earlier one is open:
-- { kind: rule, rule, regime }, { kind: asks, asks } or { kind: not_covered }.
-- A date regime whose date is unknown applies and names the fact.
create or replace function ${select}(rules jsonb, facts jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rule jsonb;
  v_membership jsonb;
  v_fact text;
  v_range jsonb;
  v_judged jsonb;
  v_verdict text;
  v_regime jsonb;
  v_date date;
  v_asks text[] := '{}';
begin
  for v_rule in select e.value from jsonb_array_elements(rules) e(value) loop
    select coalesce(jsonb_object_agg(a.key, a.value) filter (where jsonb_typeof(a.value) <> 'object'), '{}'::jsonb),
      min(a.key) filter (where jsonb_typeof(a.value) = 'object')
    into v_membership, v_fact
    from jsonb_each(coalesce(v_rule -> 'applies', '{}'::jsonb)) a;
    v_judged := ${judge}(v_membership, facts);
    v_verdict := v_judged ->> 'verdict';
    v_regime := null;
    if v_verdict = 'true' and v_fact is not null then
      v_range := v_rule -> 'applies' -> v_fact;
      v_date := ${date}(facts -> v_fact);
      if v_date is null then
        v_regime := jsonb_build_object('fact', v_fact, 'from', v_range -> 'from');
      elsif not ((v_range ->> 'from' is null or v_date >= (v_range ->> 'from')::date)
        and (v_range ->> 'before' is null or v_date < (v_range ->> 'before')::date)) then
        v_verdict := 'false';
      end if;
    end if;
    if v_verdict = 'true' and cardinality(v_asks) = 0 then
      return jsonb_build_object('kind', 'rule', 'rule', v_rule, 'regime', v_regime);
    end if;
    if v_verdict = 'unknown' then
      v_asks := v_asks || array(select jsonb_array_elements_text(v_judged -> 'asks'));
    end if;
  end loop;
  if cardinality(v_asks) > 0 then
    return jsonb_build_object('kind', 'asks', 'asks', to_jsonb(v_asks));
  end if;
  return jsonb_build_object('kind', 'not_covered');
end;
$$;
${helperGrant(`${select}(jsonb, jsonb)`)}

-- One group of a version for the facts: one result, or one per month for a
-- periodic rule.
create or replace function ${group}(content jsonb, deadline_group jsonb, facts jsonb, as_of date)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_counting jsonb := case when jsonb_typeof(content -> 'counting') = 'object' then content -> 'counting' end;
  v_selection jsonb;
  v_rule jsonb;
  v_base jsonb;
  v_regime_marks jsonb := '[]'::jsonb;
  v_rule_marks jsonb := '[]'::jsonb;
  v_counting_marks jsonb := '[]'::jsonb;
  v_unsettled jsonb := '[]'::jsonb;
  v_regime_asks text[] := '{}';
  v_open text[] := '{}';
  v_exception jsonb;
  v_when jsonb;
  v_unless jsonb;
  v_status text;
  v_deadline jsonb;
  v_rolls boolean;
  v_months jsonb;
  v_outcome jsonb;
  v_missing jsonb;
  v_result text;
  v_month date;
  v_results jsonb := '[]'::jsonb;
begin
  v_base := jsonb_build_object('group', deadline_group -> 'key', 'ruleKey', null, 'period', null, 'result', 'not_covered',
    'dueOn', null, 'provisional', false, 'missing', '[]'::jsonb, 'exception', null, 'review', '[]'::jsonb,
    'basis', null, 'deadline', null, 'citation', deadline_group -> 'citation');
  v_selection := ${select}(coalesce((select jsonb_agg(e.value order by e.ord) from jsonb_array_elements(content -> 'rules') with ordinality e(value, ord)
    where e.value -> 'group' = deadline_group -> 'key'), '[]'::jsonb), facts);
  if v_selection ->> 'kind' = 'asks' then
    return jsonb_build_array(v_base || jsonb_build_object('result', 'unknown',
      'missing', ${sortedText}(array(select jsonb_array_elements_text(v_selection -> 'asks')))));
  end if;
  if v_selection ->> 'kind' = 'not_covered' then
    return jsonb_build_array(v_base);
  end if;
  v_rule := v_selection -> 'rule';
  if jsonb_typeof(v_selection -> 'regime') = 'object' then
    v_regime_marks := jsonb_build_array(jsonb_build_object('kind', 'regime') || (v_selection -> 'regime'));
    v_regime_asks := array[v_selection #>> '{regime,fact}'];
  end if;
  v_status := coalesce(v_rule ->> 'status', 'approved');
  if v_status <> 'approved' then
    v_rule_marks := jsonb_build_array(jsonb_build_object('kind', 'rule', 'status', v_status));
  end if;
  v_deadline := v_rule -> 'deadline';
  v_base := v_base || jsonb_build_object('ruleKey', v_rule -> 'key', 'deadline', coalesce(v_deadline, 'null'::jsonb), 'citation', v_rule -> 'citation');
  if v_rule -> 'required' = 'false'::jsonb then
    v_missing := ${sortedText}(v_regime_asks);
    return jsonb_build_array(v_base || jsonb_build_object('result', 'not_required', 'citation', deadline_group -> 'citation',
      'missing', v_missing, 'provisional', jsonb_array_length(v_missing) > 0, 'review', v_regime_marks || v_rule_marks));
  end if;
  for v_exception in select e.value from jsonb_array_elements(coalesce(v_rule -> 'exceptions', '[]'::jsonb)) e(value) loop
    v_when := ${judge}(v_exception -> 'when', facts);
    v_unless := case when v_exception ? 'unless' then ${judge}(v_exception -> 'unless', facts) else jsonb_build_object('verdict', 'false', 'asks', '[]'::jsonb) end;
    if v_when ->> 'verdict' = 'false' or v_unless ->> 'verdict' = 'true' then
      continue;
    end if;
    if v_when ->> 'verdict' = 'true' and v_unless ->> 'verdict' = 'false' then
      if v_exception ->> 'result' <> 'review_required' and coalesce(v_exception ->> 'status', 'approved') <> 'review_required' then
        v_missing := ${sortedText}(v_regime_asks || v_open);
        return jsonb_build_array(v_base || jsonb_build_object('result', v_exception ->> 'result',
          'exception', jsonb_build_object('name', v_exception -> 'name', 'citation', v_exception -> 'citation')
            || case when v_exception ? 'remedy' then jsonb_build_object('remedy', v_exception -> 'remedy') else '{}'::jsonb end
            || case when v_exception ? 'note' then jsonb_build_object('note', v_exception -> 'note') else '{}'::jsonb end,
          'missing', v_missing, 'provisional', jsonb_array_length(v_missing) > 0, 'review', v_regime_marks || v_rule_marks));
      end if;
      v_unsettled := v_unsettled || jsonb_build_array(jsonb_build_object('kind', 'exception', 'name', v_exception -> 'name', 'citation', v_exception -> 'citation')
        || case when v_exception ? 'note' then jsonb_build_object('note', v_exception -> 'note') else '{}'::jsonb end);
      continue;
    end if;
    v_open := v_open || array(select jsonb_array_elements_text(v_when -> 'asks')) || array(select jsonb_array_elements_text(v_unless -> 'asks'));
  end loop;
  if v_counting is not null and coalesce(v_counting ->> 'status', 'approved') <> 'approved' then
    v_counting_marks := jsonb_build_array(jsonb_build_object('kind', 'counting', 'status', v_counting ->> 'status'));
  end if;
  v_rolls := v_deadline is not null and jsonb_typeof(v_deadline) <> 'null' and not exists (
    select 1 from jsonb_array_elements(case
      when jsonb_typeof(v_deadline) <> 'object' then '[]'::jsonb
      when v_deadline ? 'first_of' then v_deadline -> 'first_of'
      when v_deadline ? 'earlier_of' then v_deadline -> 'earlier_of'
      when v_deadline ? 'later_of' then v_deadline -> 'later_of'
      else jsonb_build_array(v_deadline) end) c(value)
    where c.value ? 'before');
  if jsonb_typeof(v_deadline) = 'object' and v_deadline ->> 'each' = 'furnishing_month' then
    v_months := ${periods}(facts, as_of);
    if jsonb_array_length(v_months -> 'months') = 0 then
      v_missing := ${sortedText}(v_regime_asks || v_open || array(select jsonb_array_elements_text(v_months -> 'asks')));
      v_result := case when jsonb_array_length(v_months -> 'asks') > 0 then 'unknown' else 'pending' end;
      return jsonb_build_array(v_base || jsonb_build_object('result', v_result, 'missing', v_missing,
        'provisional', v_result <> 'unknown' and jsonb_array_length(v_missing) > 0,
        'review', v_regime_marks || v_unsettled || v_rule_marks));
    end if;
    v_missing := ${sortedText}(v_regime_asks || v_open);
    for v_month in select (e.value #>> '{}')::date from jsonb_array_elements(v_months -> 'months') e(value) loop
      v_results := v_results || jsonb_build_array(v_base || jsonb_build_object('result', 'due',
        'period', to_char(v_month, 'YYYY-MM'),
        'dueOn', to_char(${roll}(v_counting, ${add}(v_month, v_deadline, v_counting), v_rolls, v_rule ->> 'adjust'), 'YYYY-MM-DD'),
        'basis', jsonb_build_object('anchor', jsonb_build_object('fact', coalesce(v_deadline ->> 'from', ''), 'date', to_char(v_month, 'YYYY-MM-DD')), 'without', '[]'::jsonb),
        'missing', v_missing, 'provisional', jsonb_array_length(v_missing) > 0,
        'review', v_regime_marks || v_unsettled || v_counting_marks || v_rule_marks));
    end loop;
    return v_results;
  end if;
  v_outcome := ${outcome}(v_deadline, facts, v_counting);
  v_result := v_outcome ->> 'result';
  v_missing := ${sortedText}(v_regime_asks || v_open || array(select jsonb_array_elements_text(v_outcome -> 'asks')));
  return jsonb_build_array(v_base || jsonb_build_object('result', v_result,
    'dueOn', case when v_result = 'due' then to_char(${roll}(v_counting, (v_outcome ->> 'due')::date, v_rolls, v_rule ->> 'adjust'), 'YYYY-MM-DD') end,
    'basis', v_outcome -> 'basis',
    'missing', v_missing, 'provisional', v_result <> 'unknown' and jsonb_array_length(v_missing) > 0,
    'review', v_regime_marks || v_unsettled || case when v_result = 'due' then v_counting_marks else '[]'::jsonb end || v_rule_marks));
end;
$$;
${helperGrant(`${group}(jsonb, jsonb, jsonb, date)`)}

-- Bars a group that requires a barred group, to a fixed point. results is an
-- object of group key to its results; only a group without a refusal of its
-- own falls.
create or replace function ${cascade}(results jsonb, groups jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_results jsonb := results;
  v_group jsonb;
  v_first jsonb;
  v_barring jsonb;
  v_changed boolean := true;
begin
  while v_changed loop
    v_changed := false;
    for v_group in select e.value from jsonb_array_elements(groups) e(value) loop
      v_first := v_results -> (v_group ->> 'key') -> 0;
      if v_first is null or not (v_first ->> 'result' in ('due', 'unknown', 'pending', 'undated')) then
        continue;
      end if;
      select v_results -> r.key -> 0 into v_barring
      from jsonb_array_elements_text(coalesce(v_group -> 'requires', '[]'::jsonb)) with ordinality r(key, ord)
      where v_results -> r.key -> 0 ->> 'result' = 'barred'
      order by r.ord limit 1;
      if v_barring is null or jsonb_typeof(v_barring -> 'exception') is distinct from 'object' then
        continue;
      end if;
      v_results := jsonb_set(v_results, array[v_group ->> 'key'], jsonb_build_array(v_first || jsonb_build_object(
        'period', null, 'result', 'barred', 'dueOn', null, 'provisional', false, 'missing', '[]'::jsonb, 'basis', null,
        'review', coalesce((select jsonb_agg(m.value order by m.ord) from jsonb_array_elements(v_first -> 'review') with ordinality m(value, ord)
          where m.value ->> 'kind' not in ('exception', 'counting')), '[]'::jsonb),
        'exception', jsonb_build_object('name', v_barring #> '{exception,name}', 'citation', v_barring #> '{exception,citation}',
          'note', 'falls with ' || (v_barring ->> 'group')))));
      v_changed := true;
    end loop;
  end loop;
  return v_results;
end;
$$;
${helperGrant(`${cascade}(jsonb, jsonb)`)}

-- Evaluates a rule set version for a subject's facts: an array of results,
-- one per group in the version's order (one per month for a periodic rule),
-- or only group_key's. as_of ends a periodic rule's months while furnishing
-- goes on.
create or replace function ${fn("evaluate_deadlines")}(content jsonb, facts jsonb, as_of date default current_date, group_key text default null)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_groups jsonb;
  v_results jsonb := '{}'::jsonb;
  v_group jsonb;
  v_facts jsonb := coalesce(facts, '{}'::jsonb);
begin
  if as_of is null then
    raise exception 'as_of is required' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  with recursive wanted(key) as (
    select group_key where group_key is not null
    union
    select r.key from wanted w
    join jsonb_array_elements(content -> 'groups') g(value) on g.value ->> 'key' = w.key
    cross join jsonb_array_elements_text(coalesce(g.value -> 'requires', '[]'::jsonb)) r(key)
  )
  select coalesce(jsonb_agg(g.value order by g.ord), '[]'::jsonb) into v_groups
  from jsonb_array_elements(content -> 'groups') with ordinality g(value, ord)
  where group_key is null or g.value ->> 'key' in (select w.key from wanted w);
  for v_group in select e.value from jsonb_array_elements(v_groups) e(value) loop
    v_results := v_results || jsonb_build_object(v_group ->> 'key', ${group}(content, v_group, v_facts, as_of));
  end loop;
  v_results := ${cascade}(v_results, v_groups);
  return coalesce((
    select jsonb_agg(r.value order by g.ord, r.ord)
    from jsonb_array_elements(v_groups) with ordinality g(value, ord)
    cross join jsonb_array_elements(v_results -> (g.value ->> 'key')) with ordinality r(value, ord)
    where group_key is null or g.value ->> 'key' = group_key
  ), '[]'::jsonb);
end;
$$;
${grant(`${fn("evaluate_deadlines")}(jsonb, jsonb, date, text)`)}
`;
}
