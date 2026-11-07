SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.deadline_add (
  anchor   date,
  count    jsonb,
  counting jsonb DEFAULT NULL::jsonb
)
  RETURNS date
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
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
    if v_left > 3650 then
      raise exception 'n is a whole number from 0 to 3650' using errcode = '22023', hint = 'DEADLINE_INVALID';
    end if;
    while v_left > 0 loop
      v_day := v_day + v_step;
      if "better_supabase"."deadline_business_day"(counting, v_day) then
        v_left := v_left - 1;
      end if;
    end loop;
    return v_day;
  end if;
  return anchor + v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.validate_deadline_rules (
  content jsonb
)
  RETURNS text[]
  LANGUAGE plpgsql
  IMMUTABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_issues text[] := '{}';
  v_name constant text := '^[a-z][a-z0-9_]{0,62}$';
  v_rule_key constant text := '^[a-z][a-z0-9_]{0,127}$';
  v_rules jsonb;
  v_groups jsonb;
  v_item jsonb;
  v_ord integer;
  v_at text;
  v_here text;
  v_key text;
  v_keys text[] := '{}';
  v_all_keys text[];
  v_requires jsonb := '{}'::jsonb;
  v_next text;
  v_fact text;
  v_value jsonb;
  v_regimes integer;
  v_combinator text;
  v_sub jsonb;
  v_sub_ord integer;
  v_names text[];
  v_counting jsonb;
  v_date jsonb;
  v_date_keys text;
begin
  if jsonb_typeof(content) is distinct from 'object' then
    return array['a rule set version is an object with rules and groups'];
  end if;
  v_rules := content -> 'rules';
  v_groups := content -> 'groups';
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) = 0 then
    v_issues := v_issues || 'a rule set version needs a non-empty list of rules'::text;
  end if;
  if jsonb_typeof(v_groups) is distinct from 'array' or jsonb_array_length(v_groups) = 0 then
    v_issues := v_issues || 'a rule set version needs a non-empty list of groups'::text;
  end if;
  if cardinality(v_issues) > 0 then
    return v_issues;
  end if;

  for v_item, v_ord in select e.value, e.ord::integer from jsonb_array_elements(v_groups) with ordinality e(value, ord) loop
    v_at := 'group ' || v_ord;
    if jsonb_typeof(v_item) <> 'object' then
      v_issues := v_issues || (v_at || ' must be an object');
      continue;
    end if;
    v_key := v_item ->> 'key';
    if jsonb_typeof(v_item -> 'key') is distinct from 'string' or v_key !~ v_name then
      v_issues := v_issues || (v_at || ' needs a key in lower case letters, digits and _');
    elsif v_key = any (v_keys) then
      v_issues := v_issues || (v_at || ' repeats the key ' || v_key);
    else
      v_keys := v_keys || v_key;
    end if;
    if v_item ? 'title' and (jsonb_typeof(v_item -> 'title') <> 'string' or char_length(v_item ->> 'title') > 200) then
      v_issues := v_issues || (v_at || ' title is text of at most 200 characters');
    end if;
    if "better_supabase"."deadline_citation_bad"(v_item -> 'citation') then
      v_issues := v_issues || (v_at || ' needs a citation with a reference');
    end if;
    if v_item ? 'meta' and "better_supabase"."deadline_meta_bad"(v_item -> 'meta') then
      v_issues := v_issues || (v_at || ' meta must be an object of at most 32768 bytes');
    end if;
  end loop;
  for v_item, v_ord in select e.value, e.ord::integer from jsonb_array_elements(v_groups) with ordinality e(value, ord) loop
    if jsonb_typeof(v_item) <> 'object' or not v_item ? 'requires' then
      continue;
    end if;
    if jsonb_typeof(v_item -> 'requires') = 'array' and not exists (
      select 1 from jsonb_array_elements(v_item -> 'requires') r
      where jsonb_typeof(r) <> 'string' or not ((r #>> '{}') = any (v_keys)) or r = v_item -> 'key'
    ) then
      if jsonb_typeof(v_item -> 'key') = 'string' then
        v_requires := v_requires || jsonb_build_object(v_item ->> 'key', v_item -> 'requires');
      end if;
    else
      v_issues := v_issues || ('group ' || v_ord || ' requires is a list of other group keys');
    end if;
  end loop;
  for v_item, v_ord in select e.value, e.ord::integer from jsonb_array_elements(v_groups) with ordinality e(value, ord) loop
    if jsonb_typeof(v_item) <> 'object' or jsonb_typeof(v_item -> 'key') is distinct from 'string' then
      continue;
    end if;
    v_key := v_item ->> 'key';
    for v_next in select r.key from jsonb_array_elements_text(coalesce(v_requires -> v_key, '[]'::jsonb)) with ordinality r(key, ord) order by r.ord loop
      if exists (
        with recursive walk(key) as (
          select v_next
          union
          select n.key from walk w cross join jsonb_array_elements_text(coalesce(v_requires -> w.key, '[]'::jsonb)) n(key)
        ) select 1 from walk where walk.key = v_key
      ) then
        v_issues := v_issues || ('group ' || v_ord || ' requires itself through ' || v_next);
        exit;
      end if;
    end loop;
  end loop;

  v_all_keys := array(select g ->> 'key' from jsonb_array_elements(v_groups) g where jsonb_typeof(g -> 'key') = 'string');
  v_keys := '{}';
  for v_item, v_ord in select e.value, e.ord::integer from jsonb_array_elements(v_rules) with ordinality e(value, ord) loop
    v_at := 'rule ' || v_ord;
    if jsonb_typeof(v_item) <> 'object' then
      v_issues := v_issues || (v_at || ' must be an object');
      continue;
    end if;
    v_key := v_item ->> 'key';
    if jsonb_typeof(v_item -> 'key') is distinct from 'string' or v_key !~ v_rule_key then
      v_issues := v_issues || (v_at || ' needs a key in lower case letters, digits and _');
    elsif v_key = any (v_keys) then
      v_issues := v_issues || (v_at || ' repeats the key ' || v_key);
    else
      v_keys := v_keys || v_key;
    end if;
    if jsonb_typeof(v_item -> 'group') is distinct from 'string' or not ((v_item ->> 'group') = any (v_all_keys)) then
      v_issues := v_issues || (v_at || ' needs a group that the version lists');
    end if;
    if v_item ? 'title' and (jsonb_typeof(v_item -> 'title') <> 'string' or char_length(v_item ->> 'title') > 200) then
      v_issues := v_issues || (v_at || ' title is text of at most 200 characters');
    end if;
    if v_item ? 'status' and not (jsonb_typeof(v_item -> 'status') = 'string' and (v_item ->> 'status') in ('approved', 'draft', 'review_required')) then
      v_issues := v_issues || (v_at || ' status is approved, draft, review_required');
    end if;
    if v_item ? 'adjust' and not (jsonb_typeof(v_item -> 'adjust') = 'string' and (v_item ->> 'adjust') in ('none', 'next_business_day', 'previous_business_day')) then
      v_issues := v_issues || (v_at || ' adjust is none, next_business_day, previous_business_day');
    end if;
    if v_item ->> 'adjust' = 'next_business_day' and jsonb_path_exists(v_item -> 'deadline', 'strict $.**.before') then
      v_issues := v_issues || (v_at || ' adjust next_business_day never follows a before count');
    end if;
    if v_item ? 'required' and jsonb_typeof(v_item -> 'required') <> 'boolean' then
      v_issues := v_issues || (v_at || ' required is true or false');
    end if;
    if "better_supabase"."deadline_citation_bad"(v_item -> 'citation') then
      v_issues := v_issues || (v_at || ' needs a citation with a reference');
    end if;

    if v_item ? 'applies' then
      if jsonb_typeof(v_item -> 'applies') <> 'object' then
        v_issues := v_issues || (v_at || ' applies must be an object');
      else
        v_regimes := 0;
        for v_fact, v_value in select a.key, a.value from jsonb_each(v_item -> 'applies') a order by a.key collate "C" loop
          if v_fact !~ v_name then
            v_issues := v_issues || (v_at || ' applies ' || v_fact || ' is not a fact name');
          elsif jsonb_typeof(v_value) = 'object' then
            v_regimes := v_regimes + 1;
            if exists (select 1 from jsonb_object_keys(v_value) k where k not in ('from', 'before'))
              or not (v_value ? 'from' or v_value ? 'before')
              or (v_value ? 'from' and "better_supabase"."deadline_date"(v_value -> 'from') is null)
              or (v_value ? 'before' and "better_supabase"."deadline_date"(v_value -> 'before') is null)
              or ("better_supabase"."deadline_date"(v_value -> 'from') >= "better_supabase"."deadline_date"(v_value -> 'before')) then
              v_issues := v_issues || (v_at || ' applies ' || v_fact || ' is a date range from before before');
            end if;
          elsif not (v_value in ('"present"'::jsonb, '"absent"'::jsonb) or "better_supabase"."deadline_codes"(v_value)) then
            v_issues := v_issues || (v_at || ' applies ' || v_fact || ' is a list of codes, present or absent');
          end if;
        end loop;
        if v_regimes > 1 then
          v_issues := v_issues || (v_at || ' selects by one date at most');
        end if;
      end if;
    end if;

    if v_item ? 'deadline' and v_item -> 'deadline' <> '"none"'::jsonb then
      v_value := v_item -> 'deadline';
      if jsonb_typeof(v_value) <> 'object' then
        v_issues := v_issues || (v_at || ' deadline is none, a count, or first_of, earlier_of, later_of with at least two counts');
      else
        v_combinator := case when v_value ? 'first_of' then 'first_of' when v_value ? 'earlier_of' then 'earlier_of' when v_value ? 'later_of' then 'later_of' end;
        if v_combinator is null then
          v_issues := v_issues || "better_supabase"."deadline_count_issues"(v_value, v_at || ' deadline', false);
        elsif (select count(*) from jsonb_object_keys(v_value)) <> 1
          or jsonb_typeof(v_value -> v_combinator) <> 'array' or jsonb_array_length(v_value -> v_combinator) < 2 then
          v_issues := v_issues || (v_at || ' deadline is none, a count, or first_of, earlier_of, later_of with at least two counts');
        else
          for v_sub, v_sub_ord in select c.value, c.ord::integer from jsonb_array_elements(v_value -> v_combinator) with ordinality c(value, ord) loop
            v_issues := v_issues || "better_supabase"."deadline_count_issues"(v_sub, v_at || ' deadline ' || v_combinator || ' ' || v_sub_ord, true);
          end loop;
        end if;
      end if;
    end if;

    if v_item ? 'exceptions' then
      if jsonb_typeof(v_item -> 'exceptions') <> 'array' then
        v_issues := v_issues || (v_at || ' exceptions must be a list');
      else
        v_names := '{}';
        for v_sub, v_sub_ord in select x.value, x.ord::integer from jsonb_array_elements(v_item -> 'exceptions') with ordinality x(value, ord) loop
          v_here := v_at || ' exception ' || v_sub_ord;
          if jsonb_typeof(v_sub) <> 'object' then
            v_issues := v_issues || (v_here || ' must be an object');
            continue;
          end if;
          if jsonb_typeof(v_sub -> 'name') is distinct from 'string' or (v_sub ->> 'name') !~ v_name then
            v_issues := v_issues || (v_here || ' needs a name in lower case letters, digits and _');
          elsif (v_sub ->> 'name') = any (v_names) then
            v_issues := v_issues || (v_here || ' repeats the name ' || (v_sub ->> 'name'));
          else
            v_names := v_names || (v_sub ->> 'name');
          end if;
          if "better_supabase"."deadline_condition_bad"(v_sub -> 'when', true) then
            v_issues := v_issues || (v_here || ' when is a non-empty condition');
          end if;
          if v_sub ? 'unless' and "better_supabase"."deadline_condition_bad"(v_sub -> 'unless', false) then
            v_issues := v_issues || (v_here || ' unless is a condition');
          end if;
          if not (jsonb_typeof(v_sub -> 'result') is not distinct from 'string' and (v_sub ->> 'result') in ('barred', 'not_applicable', 'not_required', 'review_required')) then
            v_issues := v_issues || (v_here || ' result is barred, not_applicable, not_required, review_required');
          end if;
          if v_sub ? 'remedy' and (jsonb_typeof(v_sub -> 'remedy') <> 'string' or char_length(v_sub ->> 'remedy') > 500) then
            v_issues := v_issues || (v_here || ' remedy is text of at most 500 characters');
          end if;
          if v_sub ? 'note' and (jsonb_typeof(v_sub -> 'note') <> 'string' or char_length(v_sub ->> 'note') > 2000) then
            v_issues := v_issues || (v_here || ' note is text of at most 2000 characters');
          end if;
          if v_sub ? 'status' and not (jsonb_typeof(v_sub -> 'status') = 'string' and (v_sub ->> 'status') in ('approved', 'draft', 'review_required')) then
            v_issues := v_issues || (v_here || ' status is approved, draft, review_required');
          end if;
          if "better_supabase"."deadline_citation_bad"(v_sub -> 'citation') then
            v_issues := v_issues || (v_here || ' needs a citation with a reference');
          end if;
        end loop;
      end if;
    end if;

    if v_item ? 'meta' and "better_supabase"."deadline_meta_bad"(v_item -> 'meta') then
      v_issues := v_issues || (v_at || ' meta must be an object of at most 32768 bytes');
    end if;
  end loop;

  v_counting := content -> 'counting';
  if jsonb_typeof(v_counting) = 'object' then
    if v_counting -> 'roll_to' is distinct from '"next_business_day"'::jsonb then
      v_issues := v_issues || 'counting roll_to is next_business_day'::text;
    end if;
    if jsonb_typeof(v_counting -> 'roll_when') is distinct from 'array'
      or jsonb_array_length(v_counting -> 'roll_when') = 0
      or exists (select 1 from jsonb_array_elements(v_counting -> 'roll_when') w where jsonb_typeof(w) <> 'string' or not ((w #>> '{}') in ('saturday', 'sunday', 'holiday')))
      or (select count(distinct w) from jsonb_array_elements(v_counting -> 'roll_when') w) <> jsonb_array_length(v_counting -> 'roll_when') then
      v_issues := v_issues || 'counting roll_when is a non-empty list of saturday, sunday, holiday'::text;
    end if;
    if jsonb_typeof(v_counting -> 'holidays') = 'array' then
      for v_sub, v_sub_ord in select h.value, h.ord::integer from jsonb_array_elements(v_counting -> 'holidays') with ordinality h(value, ord) loop
        v_here := 'counting holiday ' || v_sub_ord;
        if jsonb_typeof(v_sub) <> 'object' then
          v_issues := v_issues || (v_here || ' must be an object');
          continue;
        end if;
        if jsonb_typeof(v_sub -> 'name') is distinct from 'string' or (v_sub ->> 'name') = '' or char_length(v_sub ->> 'name') > 200 then
          v_issues := v_issues || (v_here || ' needs a name of at most 200 characters');
        end if;
        v_date := v_sub -> 'date';
        v_date_keys := case when jsonb_typeof(v_date) = 'object' then (select string_agg(k, ',' order by k collate "C") from jsonb_object_keys(v_date) k) end;
        if not coalesce(
          (v_date_keys = 'day,month' and "better_supabase"."deadline_whole"(v_date -> 'month', 1, 12) and "better_supabase"."deadline_whole"(v_date -> 'day', 1, 31))
          or (v_date_keys = 'month,nth,weekday' and "better_supabase"."deadline_whole"(v_date -> 'month', 1, 12)
            and jsonb_typeof(v_date -> 'weekday') = 'string' and (v_date ->> 'weekday') in ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')
            and (v_date -> 'nth' = '"last"'::jsonb or "better_supabase"."deadline_whole"(v_date -> 'nth', 1, 5))), false) then
          v_issues := v_issues || (v_here || ' date is a month and day, or a month, weekday and nth');
        end if;
        if "better_supabase"."deadline_citation_bad"(v_sub -> 'citation') then
          v_issues := v_issues || (v_here || ' needs a citation with a reference');
        end if;
        if v_sub ? 'observed' then
          if jsonb_typeof(v_sub -> 'observed') <> 'array' then
            v_issues := v_issues || (v_here || ' observed must be a list');
          else
            v_issues := v_issues || array(
              select v_here || ' observed ' || o.ord || ' needs falls_on, observe and a citation'
              from jsonb_array_elements(v_sub -> 'observed') with ordinality o(value, ord)
              where jsonb_typeof(o.value) <> 'object'
                or not coalesce((o.value ->> 'falls_on') in ('saturday', 'sunday', 'other_than_sunday') and jsonb_typeof(o.value -> 'falls_on') = 'string', false)
                or not coalesce((o.value ->> 'observe') in ('preceding_friday', 'following_monday', 'preceding_sunday', 'following_sunday') and jsonb_typeof(o.value -> 'observe') = 'string', false)
                or (o.value ? 'replaces' and jsonb_typeof(o.value -> 'replaces') <> 'boolean')
                or "better_supabase"."deadline_citation_bad"(o.value -> 'citation')
              order by o.ord);
          end if;
        end if;
      end loop;
    elsif v_counting ? 'holidays' then
      v_issues := v_issues || 'counting holidays must be a list'::text;
    end if;
    if v_counting ? 'citation' and "better_supabase"."deadline_citation_bad"(v_counting -> 'citation') then
      v_issues := v_issues || 'counting citation needs a reference'::text;
    end if;
    if v_counting ? 'status' and not (jsonb_typeof(v_counting -> 'status') = 'string' and (v_counting ->> 'status') in ('approved', 'draft', 'review_required')) then
      v_issues := v_issues || 'counting status is approved, draft, review_required'::text;
    end if;
  elsif v_counting is not null and jsonb_typeof(v_counting) <> 'null' then
    v_issues := v_issues || 'counting must be an object'::text;
  end if;

  if content ? 'meta' and jsonb_typeof(content -> 'meta') <> 'null' and "better_supabase"."deadline_meta_bad"(content -> 'meta') then
    v_issues := v_issues || 'meta must be an object of at most 32768 bytes'::text;
  end if;
  return v_issues;
end;
$function$;
