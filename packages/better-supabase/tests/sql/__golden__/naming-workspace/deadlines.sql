-- ==== schema supabase/schemas/900_better_supabase_172_deadlines.sql
-- better-supabase module: deadlines
-- @bsb-block deadlines@2 managed
-- @bsb-hash sha256:b785acb7c18a53b9332009b440e53f96cbd29cd999ed6a06631f206cd7d7dda5
-- Platform-owned rule sets per jurisdiction and kind, versioned and approved once with a content hash: ordered groups of rules with conditions, exceptions, a deadline grammar, a counting block with holidays and opaque meta. Each group yields a subject's deadline from its facts: due on a date (one per month for a periodic rule), unknown with the facts still missing, pending, undated, or not covered, not applicable, not required or barred; recomputed when facts arrive and satisfied by a recorded action.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Deadlines: rule sets owned by the platform (no tenant), versioned and approved
-- once, and the deadlines computed from a subject's facts. A version is data:
-- ordered groups, ordered rules with conditions, exceptions and a deadline
-- grammar, a counting block with holidays, and opaque meta. Each group yields
-- one deadline per subject (one per month for a periodic rule): due on a
-- date, unknown with the facts it waits for, pending, undated, or refused as
-- not covered, not applicable, not required or barred.
create table "better_supabase"."deadline_rule_sets" (
  "id" uuid primary key default gen_random_uuid(),
  "jurisdiction" text not null constraint bsb_deadline_rule_sets_jurisdiction_check check ("jurisdiction" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "kind" text not null constraint bsb_deadline_rule_sets_kind_check check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "title" text constraint bsb_deadline_rule_sets_title_check check ("title" is null or length("title") <= 200),
  "created_at" timestamptz not null default now(),
  constraint "deadline_rule_sets_key" unique ("jurisdiction", "kind")
);
alter table "better_supabase"."deadline_rule_sets" enable row level security;
revoke all on "better_supabase"."deadline_rule_sets" from public, anon, authenticated;
grant select on "better_supabase"."deadline_rule_sets" to authenticated;
grant all on "better_supabase"."deadline_rule_sets" to service_role;
create policy bsb_deadline_rule_sets_read on "better_supabase"."deadline_rule_sets"
  for select to authenticated
  using (true);

create table "better_supabase"."deadline_rule_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "rule_set_id" uuid not null references "better_supabase"."deadline_rule_sets" ("id") on delete cascade,
  "version" integer not null constraint bsb_deadline_rule_versions_version_check check ("version" >= 1),
  "status" text not null default 'draft' constraint bsb_deadline_rule_versions_status_check check ("status" in ('draft', 'approved')),
  "rules" jsonb not null,
  "groups" jsonb not null default '[]'::jsonb,
  "counting" jsonb,
  "meta" jsonb,
  "content_hash" text,
  "effective_from" date,
  "approved_by" uuid,
  "approved_at" timestamptz,
  "approval_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("rule_set_id", "version"),
  constraint bsb_deadline_rule_versions_check check ("status" = 'draft' or ("content_hash" is not null and "effective_from" is not null and "approved_at" is not null))
);
create index "deadline_rule_versions_effective_idx" on "better_supabase"."deadline_rule_versions" ("rule_set_id", "effective_from" desc) where "status" = 'approved';
alter table "better_supabase"."deadline_rule_versions" enable row level security;
revoke all on "better_supabase"."deadline_rule_versions" from public, anon, authenticated;
grant select on "better_supabase"."deadline_rule_versions" to authenticated;
grant all on "better_supabase"."deadline_rule_versions" to service_role;
create policy bsb_deadline_rule_versions_read on "better_supabase"."deadline_rule_versions"
  for select to authenticated
  using ("status" = 'approved');

-- An approved version never changes and is never deleted.
create or replace function "better_supabase"."deadline_version_frozen"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old."status" = 'approved' then
    raise exception 'an approved rule set version never changes' using errcode = '23000', hint = 'DEADLINE_RULE_VERSION_FROZEN';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."deadline_version_frozen"() from public, anon, authenticated;
create trigger bsb_deadlines_version_frozen
  before update or delete on "better_supabase"."deadline_rule_versions"
  for each row execute function "better_supabase"."deadline_version_frozen"();

create table "better_supabase"."deadlines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null constraint bsb_deadlines_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null constraint bsb_deadlines_subject_id_check check (length("subject_id") >= 1 and length("subject_id") <= 200),
  "jurisdiction" text not null,
  "kind" text not null,
  "group_key" text not null,
  "rule_key" text,
  "period" text constraint bsb_deadlines_period_check check ("period" ~ '^[0-9]{4}-[0-9]{2}$'),
  "rule_version_id" uuid not null references "better_supabase"."deadline_rule_versions" ("id") on delete restrict,
  "facts" jsonb not null default '{}'::jsonb,
  "result" text not null,
  "due_on" date,
  "provisional" boolean not null default false,
  "missing" text[] not null default '{}',
  "exception" jsonb,
  "review" jsonb not null default '[]'::jsonb,
  "basis" jsonb,
  "deadline" jsonb,
  "citation" jsonb not null,
  "as_of" date not null default current_date,
  "state" text not null default 'pending' constraint bsb_deadlines_state_check check ("state" in ('pending', 'satisfied')),
  "satisfied_at" timestamptz,
  "satisfied_by" uuid,
  "satisfied_action" text constraint bsb_deadlines_satisfied_action_check check ("satisfied_action" is null or length("satisfied_action") <= 200),
  "computed_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  constraint bsb_deadlines_result_check check ("result" in ('due', 'unknown', 'pending', 'undated', 'not_covered', 'not_applicable', 'not_required', 'barred')),
  constraint bsb_deadlines_check check (("result" = 'due') = ("due_on" is not null)),
  constraint bsb_deadlines_period_due_check check ("period" is null or "result" = 'due')
);
create unique index "bsb_deadlines_subject_group_period_key" on "better_supabase"."deadlines" ("tenant_id", "subject_type", "subject_id", "group_key", (coalesce("period", '')));
create index "deadlines_version_idx" on "better_supabase"."deadlines" ("rule_version_id");
create index "deadlines_due_idx" on "better_supabase"."deadlines" ("tenant_id", "due_on") where "state" = 'pending';
alter table "better_supabase"."deadlines" enable row level security;
revoke all on "better_supabase"."deadlines" from public, anon, authenticated;
grant select on "better_supabase"."deadlines" to authenticated;
grant all on "better_supabase"."deadlines" to service_role;

-- Whether the caller may read the subject a deadline belongs to: its row is
-- visible to them (the subject table's own policies apply) and they hold its
-- read permission, as blocks.deadlines.on or config.subjects declares it.
-- Without subjects every subject passes; with them an unlisted type fails.
-- plpgsql, so a subject table a later module creates binds late.
create or replace function "better_supabase"."deadline_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return true;
end;
$$;
revoke execute on function "better_supabase"."deadline_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."deadline_subject_readable"(text, text, uuid) to authenticated, service_role;
create policy bsb_deadlines_read on "better_supabase"."deadlines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deadlines.read')) and true);

-- An ISO date (YYYY-MM-DD) held in a jsonb string, or null.
create or replace function "better_supabase"."deadline_date"(value jsonb)
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
revoke execute on function "better_supabase"."deadline_date"(jsonb) from public, anon, authenticated;

-- Distinct text values in byte order, as a jsonb array.
create or replace function "better_supabase"."deadline_sorted"(names text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(s.x order by s.x collate "C"), '[]'::jsonb)
  from (select distinct u.x from unnest(names) u(x) where u.x is not null) s
$$;
revoke execute on function "better_supabase"."deadline_sorted"(text[]) from public, anon, authenticated;

-- A whole number from min to max held in jsonb.
create or replace function "better_supabase"."deadline_whole"(value jsonb, min_value integer, max_value integer)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) is not distinct from 'number'
    and (value #>> '{}')::numeric % 1 = 0
    and (value #>> '{}')::numeric between min_value and max_value
$$;
revoke execute on function "better_supabase"."deadline_whole"(jsonb, integer, integer) from public, anon, authenticated;

-- The days a counting block's holidays fall on for the dates listed in a year.
create or replace function "better_supabase"."deadline_holidays_of"(holidays jsonb, year integer)
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
      v_wanted := array_position(array['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'], v_holiday #>> '{date,weekday}');
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
revoke execute on function "better_supabase"."deadline_holidays_of"(jsonb, integer) from public, anon, authenticated;

-- Whether a day is a holiday of a counting block: listed in its year, or
-- observed from a date listed in the year before or after.
create or replace function "better_supabase"."deadline_is_holiday"(counting jsonb, day date)
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
  return day = any ("better_supabase"."deadline_holidays_of"(v_holidays, v_year - 1) || "better_supabase"."deadline_holidays_of"(v_holidays, v_year) || "better_supabase"."deadline_holidays_of"(v_holidays, v_year + 1));
end;
$$;
revoke execute on function "better_supabase"."deadline_is_holiday"(jsonb, date) from public, anon, authenticated;

-- Not a weekend, and not a holiday of an approved counting block.
create or replace function "better_supabase"."deadline_business_day"(counting jsonb, day date)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select extract(isodow from day) < 6
    and not (jsonb_typeof(counting) is not distinct from 'object'
      and coalesce(counting ->> 'status', 'approved') = 'approved'
      and "better_supabase"."deadline_is_holiday"(counting, day))
$$;
revoke execute on function "better_supabase"."deadline_business_day"(jsonb, date) from public, anon, authenticated;

-- The date a count yields from an anchor date, before any roll.
create or replace function "better_supabase"."deadline_add"(anchor date, count jsonb, counting jsonb default null)
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
$$;
revoke execute on function "better_supabase"."deadline_add"(date, jsonb, jsonb) from public, anon, authenticated;

-- A last day rolled past the days an approved counting block names (when the
-- deadline rolls), then moved off a non-business day by the rule's adjust.
create or replace function "better_supabase"."deadline_roll"(counting jsonb, day date, rolls boolean, adjust text)
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
      or (v_when ? 'holiday' and "better_supabase"."deadline_is_holiday"(counting, v_day)) loop
      v_day := v_day + 1;
    end loop;
  end if;
  if coalesce(adjust, 'none') <> 'none' then
    v_step := case when adjust = 'next_business_day' then 1 else -1 end;
    while not "better_supabase"."deadline_business_day"(counting, v_day) loop
      v_day := v_day + v_step;
    end loop;
  end if;
  return v_day;
end;
$$;
revoke execute on function "better_supabase"."deadline_roll"(jsonb, date, boolean, text) from public, anon, authenticated;

-- One count against the facts: { state: dated, due, fact, anchor } when its
-- fact holds a date, { state: skipped } when the fact is null, and
-- { state: unanswered, asks } otherwise.
create or replace function "better_supabase"."deadline_candidate"(count jsonb, facts jsonb, counting jsonb)
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
  v_anchor := "better_supabase"."deadline_date"(facts -> v_fact);
  if v_anchor is null then
    return jsonb_build_object('state', 'unanswered', 'asks', jsonb_build_array(v_fact));
  end if;
  return jsonb_build_object('state', 'dated', 'due', "better_supabase"."deadline_add"(v_anchor, count, counting), 'fact', v_fact, 'anchor', v_anchor);
end;
$$;
revoke execute on function "better_supabase"."deadline_candidate"(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- A rule's deadline against the facts, before any roll: { result: due |
-- unknown | pending | undated, due, asks, basis }.
create or replace function "better_supabase"."deadline_outcome"(deadline jsonb, facts jsonb, counting jsonb)
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
    v_candidate := "better_supabase"."deadline_candidate"(v_count, facts, counting);
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
revoke execute on function "better_supabase"."deadline_outcome"(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- A monthly count's months as their first days, or what it waits for: from
-- the first furnishing month through the last, or while furnishing goes on
-- through the month of as_of and one ahead.
create or replace function "better_supabase"."deadline_periods"(facts jsonb, as_of date)
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
  if facts -> 'first_furnishing_date' = 'null'::jsonb then
    return jsonb_build_object('months', '[]'::jsonb, 'asks', '[]'::jsonb);
  end if;
  v_first := "better_supabase"."deadline_date"(facts -> 'first_furnishing_date');
  if v_first is null then
    return jsonb_build_object('months', '[]'::jsonb, 'asks', jsonb_build_array('first_furnishing_date'));
  end if;
  v_last := "better_supabase"."deadline_date"(facts -> 'last_furnishing_date');
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
revoke execute on function "better_supabase"."deadline_periods"(jsonb, date) from public, anon, authenticated;

-- A three-valued AND of a condition's entries: { verdict: true | false |
-- unknown, asks }. A missing fact is unknown; null is absent for present and
-- absent, and unknown otherwise.
create or replace function "better_supabase"."deadline_judge"(condition jsonb, facts jsonb)
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
revoke execute on function "better_supabase"."deadline_judge"(jsonb, jsonb) from public, anon, authenticated;

-- The first rule of a group that applies, unless an earlier one is open:
-- { kind: rule, rule, regime }, { kind: asks, asks } or { kind: not_covered }.
-- A date regime whose date is unknown applies and names the fact.
create or replace function "better_supabase"."deadline_select_rule"(rules jsonb, facts jsonb)
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
    v_judged := "better_supabase"."deadline_judge"(v_membership, facts);
    v_verdict := v_judged ->> 'verdict';
    v_regime := null;
    if v_verdict = 'true' and v_fact is not null then
      v_range := v_rule -> 'applies' -> v_fact;
      v_date := "better_supabase"."deadline_date"(facts -> v_fact);
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
revoke execute on function "better_supabase"."deadline_select_rule"(jsonb, jsonb) from public, anon, authenticated;

-- One group of a version for the facts: one result, or one per month for a
-- periodic rule.
create or replace function "better_supabase"."deadline_group"(content jsonb, deadline_group jsonb, facts jsonb, as_of date)
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
  v_selection := "better_supabase"."deadline_select_rule"(coalesce((select jsonb_agg(e.value order by e.ord) from jsonb_array_elements(content -> 'rules') with ordinality e(value, ord)
    where e.value -> 'group' = deadline_group -> 'key'), '[]'::jsonb), facts);
  if v_selection ->> 'kind' = 'asks' then
    return jsonb_build_array(v_base || jsonb_build_object('result', 'unknown',
      'missing', "better_supabase"."deadline_sorted"(array(select jsonb_array_elements_text(v_selection -> 'asks')))));
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
    v_missing := "better_supabase"."deadline_sorted"(v_regime_asks);
    return jsonb_build_array(v_base || jsonb_build_object('result', 'not_required', 'citation', deadline_group -> 'citation',
      'missing', v_missing, 'provisional', jsonb_array_length(v_missing) > 0, 'review', v_regime_marks || v_rule_marks));
  end if;
  for v_exception in select e.value from jsonb_array_elements(coalesce(v_rule -> 'exceptions', '[]'::jsonb)) e(value) loop
    v_when := "better_supabase"."deadline_judge"(v_exception -> 'when', facts);
    v_unless := case when v_exception ? 'unless' then "better_supabase"."deadline_judge"(v_exception -> 'unless', facts) else jsonb_build_object('verdict', 'false', 'asks', '[]'::jsonb) end;
    if v_when ->> 'verdict' = 'false' or v_unless ->> 'verdict' = 'true' then
      continue;
    end if;
    if v_when ->> 'verdict' = 'true' and v_unless ->> 'verdict' = 'false' then
      if v_exception ->> 'result' <> 'review_required' and coalesce(v_exception ->> 'status', 'approved') <> 'review_required' then
        v_missing := "better_supabase"."deadline_sorted"(v_regime_asks || v_open);
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
    v_months := "better_supabase"."deadline_periods"(facts, as_of);
    if jsonb_array_length(v_months -> 'months') = 0 then
      v_missing := "better_supabase"."deadline_sorted"(v_regime_asks || v_open || array(select jsonb_array_elements_text(v_months -> 'asks')));
      v_result := case when jsonb_array_length(v_months -> 'asks') > 0 then 'unknown' else 'pending' end;
      return jsonb_build_array(v_base || jsonb_build_object('result', v_result, 'missing', v_missing,
        'provisional', v_result <> 'unknown' and jsonb_array_length(v_missing) > 0,
        'review', v_regime_marks || v_unsettled || v_rule_marks));
    end if;
    v_missing := "better_supabase"."deadline_sorted"(v_regime_asks || v_open);
    for v_month in select (e.value #>> '{}')::date from jsonb_array_elements(v_months -> 'months') e(value) loop
      v_results := v_results || jsonb_build_array(v_base || jsonb_build_object('result', 'due',
        'period', to_char(v_month, 'YYYY-MM'),
        'dueOn', to_char("better_supabase"."deadline_roll"(v_counting, "better_supabase"."deadline_add"(v_month, v_deadline, v_counting), v_rolls, v_rule ->> 'adjust'), 'YYYY-MM-DD'),
        'basis', jsonb_build_object('anchor', jsonb_build_object('fact', coalesce(v_deadline ->> 'from', ''), 'date', to_char(v_month, 'YYYY-MM-DD')), 'without', '[]'::jsonb),
        'missing', v_missing, 'provisional', jsonb_array_length(v_missing) > 0,
        'review', v_regime_marks || v_unsettled || v_counting_marks || v_rule_marks));
    end loop;
    return v_results;
  end if;
  v_outcome := "better_supabase"."deadline_outcome"(v_deadline, facts, v_counting);
  v_result := v_outcome ->> 'result';
  v_missing := "better_supabase"."deadline_sorted"(v_regime_asks || v_open || array(select jsonb_array_elements_text(v_outcome -> 'asks')));
  return jsonb_build_array(v_base || jsonb_build_object('result', v_result,
    'dueOn', case when v_result = 'due' then to_char("better_supabase"."deadline_roll"(v_counting, (v_outcome ->> 'due')::date, v_rolls, v_rule ->> 'adjust'), 'YYYY-MM-DD') end,
    'basis', v_outcome -> 'basis',
    'missing', v_missing, 'provisional', v_result <> 'unknown' and jsonb_array_length(v_missing) > 0,
    'review', v_regime_marks || v_unsettled || case when v_result = 'due' then v_counting_marks else '[]'::jsonb end || v_rule_marks));
end;
$$;
revoke execute on function "better_supabase"."deadline_group"(jsonb, jsonb, jsonb, date) from public, anon, authenticated;

-- Bars a group that requires a barred group, to a fixed point. results is an
-- object of group key to its results; only a group without a refusal of its
-- own falls.
create or replace function "better_supabase"."deadline_cascade"(results jsonb, groups jsonb)
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
revoke execute on function "better_supabase"."deadline_cascade"(jsonb, jsonb) from public, anon, authenticated;

-- Evaluates a rule set version for a subject's facts: an array of results,
-- one per group in the version's order (one per month for a periodic rule),
-- or only group_key's. as_of ends a periodic rule's months while furnishing
-- goes on.
create or replace function "better_supabase"."evaluate_deadlines"(content jsonb, facts jsonb, as_of date default current_date, group_key text default null)
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
    v_results := v_results || jsonb_build_object(v_group ->> 'key', "better_supabase"."deadline_group"(content, v_group, v_facts, as_of));
  end loop;
  v_results := "better_supabase"."deadline_cascade"(v_results, v_groups);
  return coalesce((
    select jsonb_agg(r.value order by g.ord, r.ord)
    from jsonb_array_elements(v_groups) with ordinality g(value, ord)
    cross join jsonb_array_elements(v_results -> (g.value ->> 'key')) with ordinality r(value, ord)
    where group_key is null or g.value ->> 'key' = group_key
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."evaluate_deadlines"(jsonb, jsonb, date, text) from public, anon;
grant execute on function "better_supabase"."evaluate_deadlines"(jsonb, jsonb, date, text) to authenticated, service_role;


-- Validation helpers: a citation without a reference, a meta that is not an
-- object of at most 32768 bytes, a list of distinct codes, a condition.
create or replace function "better_supabase"."deadline_citation_bad"(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) is distinct from 'object'
    or jsonb_typeof(value -> 'reference') is distinct from 'string'
    or (value ->> 'reference') !~ '[^[:space:]]'
$$;
revoke execute on function "better_supabase"."deadline_citation_bad"(jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."deadline_meta_bad"(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) is distinct from 'object' or octet_length(value::text) > 32768
$$;
revoke execute on function "better_supabase"."deadline_meta_bad"(jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."deadline_codes"(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) is not distinct from 'array'
    and jsonb_array_length(value) > 0
    and not exists (select 1 from jsonb_array_elements(value) e where jsonb_typeof(e) <> 'string' or e = '""'::jsonb)
    and (select count(distinct e) from jsonb_array_elements(value) e) = jsonb_array_length(value)
$$;
revoke execute on function "better_supabase"."deadline_codes"(jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."deadline_condition_bad"(value jsonb, non_empty boolean)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) is distinct from 'object'
    or (non_empty and value = '{}'::jsonb)
    or exists (
      select 1 from jsonb_each(value) e
      where e.key !~ '^[a-z][a-z0-9_]{0,62}$'
        or not (jsonb_typeof(e.value) = 'boolean'
          or (jsonb_typeof(e.value) = 'string' and e.value <> '""'::jsonb)
          or "better_supabase"."deadline_codes"(e.value))
    )
$$;
revoke execute on function "better_supabase"."deadline_condition_bad"(jsonb, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."deadline_count_issues"(count jsonb, at text, inside boolean)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_issues text[] := '{}';
  v_name constant text := '^[a-z][a-z0-9_]{0,62}$';
begin
  if jsonb_typeof(count) is distinct from 'object' then
    return array[at || ' must be a count'];
  end if;
  if (count ? 'from') = (count ? 'before')
    or (count ? 'from' and (jsonb_typeof(count -> 'from') <> 'string' or (count ->> 'from') !~ v_name))
    or (count ? 'before' and (jsonb_typeof(count -> 'before') <> 'string' or (count ->> 'before') !~ v_name)) then
    v_issues := v_issues || (at || ' counts from or before one fact');
  end if;
  if count ? 'n' and not "better_supabase"."deadline_whole"(count -> 'n', 0, 3650) then
    v_issues := v_issues || (at || ' n is a whole number from 0 to 3650');
  end if;
  if count ? 'unit' and not (jsonb_typeof(count -> 'unit') = 'string' and (count ->> 'unit') in ('days', 'business_days', 'months')) then
    v_issues := v_issues || (at || ' unit is days, business_days, months');
  end if;
  if count ? 'n' and not count ? 'unit' then
    v_issues := v_issues || (at || ' n needs a unit');
  end if;
  if count ? 'from' and not count ? 'n' then
    v_issues := v_issues || (at || ' from needs n');
  end if;
  if count ? 'day_of_month' and (not "better_supabase"."deadline_whole"(count -> 'day_of_month', 1, 28) or count -> 'unit' is distinct from '"months"'::jsonb) then
    v_issues := v_issues || (at || ' day_of_month is 1 to 28 with unit months');
  end if;
  if count ? 'each' then
    if inside then
      v_issues := v_issues || (at || ' each is not allowed inside a combinator');
    elsif count -> 'each' is distinct from '"furnishing_month"'::jsonb or not count ? 'from' or not count ? 'n' then
      v_issues := v_issues || (at || ' each is furnishing_month on a count from a fact');
    end if;
  end if;
  return v_issues;
end;
$$;
revoke execute on function "better_supabase"."deadline_count_issues"(jsonb, text, boolean) from public, anon, authenticated;

-- The problems of a rule set version's content, as text, empty when it can be
-- saved. validateRuleVersion finds the same ones in the same order.
create or replace function "better_supabase"."validate_deadline_rules"(content jsonb)
returns text[]
language plpgsql
immutable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."validate_deadline_rules"(jsonb) from public, anon;
grant execute on function "better_supabase"."validate_deadline_rules"(jsonb) to authenticated, service_role;

-- The SHA-256 content hash of a rule set version: its rules, groups,
-- counting block and meta.
create or replace function "better_supabase"."version_content_hash"(rules jsonb, groups jsonb, counting jsonb, meta jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object('rules', rules, 'groups', groups, 'counting', counting, 'meta', meta)::text, 'UTF8'), 'sha256'), 'hex')
$$;
revoke execute on function "better_supabase"."version_content_hash"(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- A rule of the version 1 shape (anchor, offset, requires) as a rule of
-- its own group: the offset counts from the anchor, or before it when it is
-- negative, and each required fact must be present.
create or replace function "better_supabase"."deadline_rule_from_v1"(rule jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
      'key', rule -> 'key',
      'group', rule -> 'key',
      'deadline', jsonb_build_object(
        'n', abs((rule #>> '{offset,amount}')::integer),
        'unit', rule #> '{offset,unit}',
        case when (rule #>> '{offset,amount}')::integer < 0 then 'before' else 'from' end, rule -> 'anchor'),
      'citation', rule -> 'citation')
    || case when rule ? 'title' then jsonb_build_object('title', rule -> 'title') else '{}'::jsonb end
    || case when rule ? 'adjust' then jsonb_build_object('adjust', rule -> 'adjust') else '{}'::jsonb end
    || coalesce((
      select jsonb_build_object('applies', jsonb_object_agg(r.name, 'present'))
      from jsonb_array_elements_text(case when jsonb_typeof(rule -> 'requires') = 'array' then rule -> 'requires' else '[]'::jsonb end) r(name)
      having count(*) > 0
    ), '{}'::jsonb)
$$;
revoke execute on function "better_supabase"."deadline_rule_from_v1"(jsonb) from public, anon, authenticated;

-- Saves a rule set version's content ({ rules, groups, counting?, meta? }) as
-- a new draft version, creating the rule set on first use. A draft is replaced
-- by the next save until it is approved. Service role only.
create or replace function "better_supabase"."save_rule_version"(jurisdiction text, kind text, content jsonb, effective_from date default null, title text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_set "better_supabase"."deadline_rule_sets";
  v_row "better_supabase"."deadline_rule_versions";
  v_issues text[];
  v_counting jsonb := case when jsonb_typeof(save_rule_version.content -> 'counting') = 'object' then save_rule_version.content -> 'counting' end;
  v_meta jsonb := case when jsonb_typeof(save_rule_version.content -> 'meta') = 'object' then save_rule_version.content -> 'meta' end;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role may save rule set versions' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if save_rule_version.jurisdiction is null or save_rule_version.jurisdiction !~ '^[a-z][a-z0-9_-]{0,62}$'
    or save_rule_version.kind is null or save_rule_version.kind !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a rule set has a lower case jurisdiction and kind' using errcode = '22023', hint = 'DEADLINE_RULES_INVALID';
  end if;
  v_issues := "better_supabase"."validate_deadline_rules"(save_rule_version.content);
  if cardinality(v_issues) > 0 then
    raise exception 'invalid rules: %', array_to_string(v_issues, '; ') using errcode = '22023', hint = 'DEADLINE_RULES_INVALID', detail = jsonb_build_object('issues', to_jsonb(v_issues))::text;
  end if;
  insert into "better_supabase"."deadline_rule_sets" ("jurisdiction", "kind", "title")
  values (save_rule_version.jurisdiction, save_rule_version.kind, nullif(btrim(save_rule_version.title), ''))
  on conflict on constraint "deadline_rule_sets_key" do update set "title" = coalesce(nullif(btrim(save_rule_version.title), ''), "better_supabase"."deadline_rule_sets"."title")
  returning * into v_set;
  select * into v_row from "better_supabase"."deadline_rule_versions" x
  where x."rule_set_id" = v_set."id" and x."status" = 'draft'
  order by x."version" desc limit 1 for update;
  if found then
    update "better_supabase"."deadline_rule_versions" x set "rules" = save_rule_version.content -> 'rules', "groups" = save_rule_version.content -> 'groups',
      "counting" = v_counting, "meta" = v_meta, "effective_from" = save_rule_version.effective_from
    where x."id" = v_row."id" returning * into v_row;
  else
    insert into "better_supabase"."deadline_rule_versions" ("rule_set_id", "version", "rules", "groups", "counting", "meta", "effective_from")
    values (v_set."id", coalesce((select max(y."version") from "better_supabase"."deadline_rule_versions" y where y."rule_set_id" = v_set."id"), 0) + 1,
      save_rule_version.content -> 'rules', save_rule_version.content -> 'groups', v_counting, v_meta, save_rule_version.effective_from)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'groups', v_row."groups", 'counting', v_row."counting", 'meta', v_row."meta", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."save_rule_version"(text, text, jsonb, date, text) from public, anon, authenticated;
grant execute on function "better_supabase"."save_rule_version"(text, text, jsonb, date, text) to service_role;

-- Approves a draft version: freezes its content with a SHA-256 content hash and
-- records who approved it and from which date it applies. Service role only.
create or replace function "better_supabase"."approve_rule_version"(version_id uuid, approval_id uuid default null, effective_from date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."deadline_rule_versions";
  v_status text;
  v_from date;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role may approve rule set versions' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."deadline_rule_versions" x where x."id" = approve_rule_version.version_id for update;
  if not found then
    raise exception 'no such rule set version' using errcode = 'P0002', hint = 'DEADLINE_RULES_NOT_FOUND';
  end if;
  if v_row."status" = 'approved' then
    return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'groups', v_row."groups", 'counting', v_row."counting", 'meta', v_row."meta", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
  end if;
  v_from := coalesce(approve_rule_version.effective_from, v_row."effective_from");
  if v_from is null then
    raise exception 'an approved version needs the date it applies from' using errcode = '22023', hint = 'DEADLINE_RULES_INVALID';
  end if;
  
  update "better_supabase"."deadline_rule_versions" x set
    "status" = 'approved',
    "effective_from" = v_from,
    "content_hash" = "better_supabase"."version_content_hash"(v_row."rules", v_row."groups", v_row."counting", v_row."meta"),
    "approved_by" = auth.uid(),
    "approved_at" = now(),
    "approval_id" = approve_rule_version.approval_id
  where x."id" = v_row."id" returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'groups', v_row."groups", 'counting', v_row."counting", 'meta', v_row."meta", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."approve_rule_version"(uuid, uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."approve_rule_version"(uuid, uuid, date) to service_role;

-- The approved version of a rule set that applies on a date: the latest one
-- that takes effect on or before it, or null.
create or replace function "better_supabase"."rule_version_at"(jurisdiction text, kind text, on_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."deadline_rule_versions";
begin
  select x.* into v_row from "better_supabase"."deadline_rule_versions" x
  join "better_supabase"."deadline_rule_sets" z on z."id" = x."rule_set_id"
  where z."jurisdiction" = rule_version_at.jurisdiction and z."kind" = rule_version_at.kind
    and x."status" = 'approved' and x."effective_from" <= rule_version_at.on_date
  order by x."effective_from" desc, x."version" desc limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'groups', v_row."groups", 'counting', v_row."counting", 'meta', v_row."meta", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."rule_version_at"(text, text, date) from public, anon;
grant execute on function "better_supabase"."rule_version_at"(text, text, date) to authenticated, service_role;

-- Stores evaluated results for a subject: one row per group and period,
-- upserted on the unique index. A satisfied row stays as it is; a pending row
-- of the groups whose results these are and that has no result any more is
-- deleted. Records deadline.computed for every row it inserts or changes, and
-- returns { rows, changed }. The callers check permissions.
create or replace function "better_supabase"."deadline_store"(p_tenant uuid, p_subject_type text, p_subject_id text, p_jurisdiction text, p_kind text, p_version_id uuid, p_facts jsonb, p_as_of date, p_results jsonb, p_group_keys text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_row "better_supabase"."deadlines";
  v_rows jsonb := '[]'::jsonb;
  v_changed integer := 0;
  v_missing text[];
  v_deleted integer;
begin
  for v_result in select e.value from jsonb_array_elements(p_results) e(value) loop
    v_missing := array(select jsonb_array_elements_text(v_result -> 'missing'));
    select * into v_row from "better_supabase"."deadlines" x
    where x."tenant_id" = p_tenant and x."subject_type" = p_subject_type
      and x."subject_id" = p_subject_id and x."group_key" = v_result ->> 'group'
      and coalesce(x."period", '') = coalesce(v_result ->> 'period', '')
    for update;
    if found and (v_row."state" = 'satisfied' or (
      v_row."rule_version_id" = p_version_id and v_row."facts" = p_facts
      and v_row."rule_key" is not distinct from v_result ->> 'ruleKey' and v_row."result" = v_result ->> 'result'
      and v_row."due_on" is not distinct from (v_result ->> 'dueOn')::date and v_row."provisional" = (v_result -> 'provisional')::boolean
      and v_row."missing" = v_missing and v_row."exception" is not distinct from nullif(v_result -> 'exception', 'null'::jsonb)
      and v_row."review" = v_result -> 'review' and v_row."basis" is not distinct from nullif(v_result -> 'basis', 'null'::jsonb)
      and v_row."deadline" is not distinct from nullif(v_result -> 'deadline', 'null'::jsonb) and v_row."citation" = v_result -> 'citation')) then
      v_rows := v_rows || jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional", 'missing', to_jsonb(v_row."missing"), 'exception', v_row."exception", 'review', v_row."review", 'basis', v_row."basis", 'deadline', v_row."deadline", 'citation', v_row."citation", 'asOf', v_row."as_of", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
      continue;
    end if;
    insert into "better_supabase"."deadlines" ("tenant_id", "subject_type", "subject_id", "jurisdiction", "kind", "group_key", "rule_key", "period",
      "rule_version_id", "facts", "result", "due_on", "provisional", "missing", "exception", "review", "basis", "deadline", "citation", "as_of")
    values (p_tenant, p_subject_type, p_subject_id, p_jurisdiction, p_kind,
      v_result ->> 'group', v_result ->> 'ruleKey', v_result ->> 'period', p_version_id, p_facts,
      v_result ->> 'result', (v_result ->> 'dueOn')::date, (v_result -> 'provisional')::boolean, v_missing,
      nullif(v_result -> 'exception', 'null'::jsonb), v_result -> 'review', nullif(v_result -> 'basis', 'null'::jsonb),
      nullif(v_result -> 'deadline', 'null'::jsonb), v_result -> 'citation', p_as_of)
    on conflict ("tenant_id", "subject_type", "subject_id", "group_key", (coalesce("period", ''))) do update set
      "jurisdiction" = excluded."jurisdiction", "kind" = excluded."kind", "rule_key" = excluded."rule_key",
      "rule_version_id" = excluded."rule_version_id", "facts" = excluded."facts", "result" = excluded."result",
      "due_on" = excluded."due_on", "provisional" = excluded."provisional", "missing" = excluded."missing",
      "exception" = excluded."exception", "review" = excluded."review", "basis" = excluded."basis",
      "deadline" = excluded."deadline", "citation" = excluded."citation", "as_of" = excluded."as_of",
      "computed_at" = now()
    returning * into v_row;
    null;
    v_rows := v_rows || jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional", 'missing', to_jsonb(v_row."missing"), 'exception', v_row."exception", 'review', v_row."review", 'basis', v_row."basis", 'deadline', v_row."deadline", 'citation', v_row."citation", 'asOf', v_row."as_of", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
    v_changed := v_changed + 1;
  end loop;
  delete from "better_supabase"."deadlines" x
  where x."tenant_id" = p_tenant and x."subject_type" = p_subject_type
    and x."subject_id" = p_subject_id and x."state" = 'pending'
    and x."group_key" = any (p_group_keys)
    and not exists (
      select 1 from jsonb_array_elements(p_results) r(value)
      where r.value ->> 'group' = x."group_key" and coalesce(r.value ->> 'period', '') = coalesce(x."period", '')
    );
  get diagnostics v_deleted = row_count;
  return jsonb_build_object('rows', v_rows, 'changed', v_changed + v_deleted);
end;
$$;
revoke execute on function "better_supabase"."deadline_store"(uuid, text, text, text, text, uuid, jsonb, date, jsonb, text[]) from public, anon, authenticated;

-- Computes a subject's deadlines from its facts with the rule set version that
-- applies on as_of (today by default): every group of the version, or only
-- group_key, and stores one row per group (one per month for a periodic
-- rule). Returns the rows. A satisfied row is returned unchanged and kept as
-- history. Without group_key, a pending row of this jurisdiction and kind
-- that the evaluation no longer yields (its group was dropped or yields no
-- row) is deleted. Needs deadlines.write and read access to the subject.
create or replace function "better_supabase"."compute_deadlines"(tenant uuid, subject_type text, subject_id text, jurisdiction text, kind text, facts jsonb default '{}', as_of date default current_date, group_key text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_version jsonb;
  v_results jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (compute_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', compute_deadlines.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to compute deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if compute_deadlines.subject_type is null or compute_deadlines.subject_type !~ '^[a-z][a-z0-9_]{0,62}$'
    or compute_deadlines.subject_id is null or length(compute_deadlines.subject_id) not between 1 and 200
    or compute_deadlines.facts is null or jsonb_typeof(compute_deadlines.facts) <> 'object'
    or compute_deadlines.as_of is null then
    raise exception 'a deadline needs a subject type, a subject id, facts as an object and a date' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(compute_deadlines.subject_type, compute_deadlines.subject_id, compute_deadlines.tenant)) then
    raise exception 'not allowed to compute deadlines for this subject' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  v_version := "better_supabase"."rule_version_at"(compute_deadlines.jurisdiction, compute_deadlines.kind, compute_deadlines.as_of);
  if v_version is null then
    raise exception 'no approved rule set version applies' using errcode = 'P0002', hint = 'DEADLINE_RULES_NOT_FOUND';
  end if;
  if compute_deadlines.group_key is not null and not exists (
    select 1 from jsonb_array_elements(v_version -> 'groups') g(value) where g.value ->> 'key' = compute_deadlines.group_key
  ) then
    raise exception 'the rule set has no group with this key' using errcode = 'P0002', hint = 'DEADLINE_RULE_NOT_FOUND';
  end if;
  v_results := "better_supabase"."evaluate_deadlines"(
    jsonb_build_object('rules', v_version -> 'rules', 'groups', v_version -> 'groups', 'counting', v_version -> 'counting'),
    compute_deadlines.facts, compute_deadlines.as_of, compute_deadlines.group_key);
  return "better_supabase"."deadline_store"(compute_deadlines.tenant, compute_deadlines.subject_type, compute_deadlines.subject_id,
    compute_deadlines.jurisdiction, compute_deadlines.kind, (v_version ->> 'id')::uuid, compute_deadlines.facts, compute_deadlines.as_of,
    v_results, case when compute_deadlines.group_key is null
      then array(
        select g.value ->> 'key' from jsonb_array_elements(v_version -> 'groups') g(value)
        union
        select x."group_key" from "better_supabase"."deadlines" x
        where x."tenant_id" = compute_deadlines.tenant and x."subject_type" = compute_deadlines.subject_type
          and x."subject_id" = compute_deadlines.subject_id and x."jurisdiction" = compute_deadlines.jurisdiction
          and x."kind" = compute_deadlines.kind)
      else array[compute_deadlines.group_key] end) -> 'rows';
end;
$$;
revoke execute on function "better_supabase"."compute_deadlines"(uuid, text, text, text, text, jsonb, date, text) from public, anon;
grant execute on function "better_supabase"."compute_deadlines"(uuid, text, text, text, text, jsonb, date, text) to authenticated, service_role;

-- Re-evaluates the pending deadlines of a subject after new facts arrived,
-- against the rule set version they were computed with (never a newer one),
-- for the groups the subject has rows of, and returns how many rows changed.
-- The facts are the latest stored ones merged with p_facts. Runs without a
-- permission check; the facts trigger and recompute_deadlines call it.
create or replace function "better_supabase"."deadline_recompute"(tenant text, subject_type text, subject_id text, p_facts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_set record;
  v_version "better_supabase"."deadline_rule_versions";
  v_facts jsonb;
  v_groups text[];
  v_results jsonb;
  v_changed integer := 0;
begin
  for v_set in
    select x."tenant_id" as tenant, x."jurisdiction" as jurisdiction, x."kind" as kind, x."rule_version_id" as version_id
    from "better_supabase"."deadlines" x
    where x."tenant_id"::text = deadline_recompute.tenant and x."subject_type" = deadline_recompute.subject_type
      and x."subject_id" = deadline_recompute.subject_id and x."state" = 'pending'
    group by 1, 2, 3, 4
  loop
    select * into v_version from "better_supabase"."deadline_rule_versions" x where x."id" = v_set.version_id;
    select y."facts" || coalesce(deadline_recompute.p_facts, '{}'::jsonb) into v_facts from "better_supabase"."deadlines" y
    where y."tenant_id" = v_set.tenant and y."subject_type" = deadline_recompute.subject_type
      and y."subject_id" = deadline_recompute.subject_id and y."rule_version_id" = v_set.version_id
    order by y."computed_at" desc, y."id" limit 1;
    v_groups := array(
      select distinct y."group_key" from "better_supabase"."deadlines" y
      where y."tenant_id" = v_set.tenant and y."subject_type" = deadline_recompute.subject_type
        and y."subject_id" = deadline_recompute.subject_id and y."rule_version_id" = v_set.version_id
    );
    v_results := coalesce((
      select jsonb_agg(r.value order by r.ord)
      from jsonb_array_elements("better_supabase"."evaluate_deadlines"(jsonb_build_object('rules', v_version."rules", 'groups', v_version."groups") || case when v_version."counting" is null then '{}'::jsonb else jsonb_build_object('counting', v_version."counting") end || case when v_version."meta" is null then '{}'::jsonb else jsonb_build_object('meta', v_version."meta") end, v_facts, current_date)) with ordinality r(value, ord)
      where r.value ->> 'group' = any (v_groups)
    ), '[]'::jsonb);
    v_changed := v_changed + ("better_supabase"."deadline_store"(v_set.tenant, deadline_recompute.subject_type, deadline_recompute.subject_id,
      v_set.jurisdiction, v_set.kind, v_set.version_id, v_facts, current_date, v_results, v_groups) ->> 'changed')::integer;
  end loop;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."deadline_recompute"(text, text, text, jsonb) from public, anon, authenticated;

-- Re-evaluates a subject's pending deadlines with extra facts. Needs
-- deadlines.write and read access to the subject.
create or replace function "better_supabase"."recompute_deadlines"(tenant uuid, subject_type text, subject_id text, facts jsonb default '{}')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (recompute_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', recompute_deadlines.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to compute deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.tenant)) then
    raise exception 'not allowed to compute deadlines for this subject' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  return "better_supabase"."deadline_recompute"(recompute_deadlines.tenant::text, recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.facts);
end;
$$;
revoke execute on function "better_supabase"."recompute_deadlines"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."recompute_deadlines"(uuid, text, text, jsonb) to authenticated, service_role;

-- A trigger function for the table that holds a subject's facts, one row per
-- fact. Attach it with an after insert row trigger and pass the subject type,
-- then the column names for the organization, subject id, fact name and value.
-- A new row recomputes the pending deadlines of its subject. The value arrives
-- as text, so a condition on a boolean fact needs recompute_deadlines with
-- typed facts instead.
create or replace function "better_supabase"."deadline_fact_trigger"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(new);
begin
  if tg_nargs <> 5 then
    raise exception 'deadline_fact_trigger takes the subject type and four column names' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  perform "better_supabase"."deadline_recompute"(v_row ->> tg_argv[1], tg_argv[0], v_row ->> tg_argv[2], jsonb_build_object(v_row ->> tg_argv[3], v_row ->> tg_argv[4]));
  return new;
end;
$$;
revoke execute on function "better_supabase"."deadline_fact_trigger"() from public, anon, authenticated;

-- Records the action that satisfied a deadline (one period of a periodic rule
-- on its own). Needs deadlines.write and read access to the subject.
create or replace function "better_supabase"."satisfy_deadline"(deadline_id uuid, action text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."deadlines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."deadlines" x where x."id" = satisfy_deadline.deadline_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deadlines.read'), false)))
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(v_row."subject_type", v_row."subject_id", v_row."tenant_id")) then
    raise exception 'no such deadline' using errcode = 'P0002', hint = 'DEADLINE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deadlines.write'), false))) then
    raise exception 'not allowed to satisfy deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if v_row."state" = 'satisfied' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional", 'missing', to_jsonb(v_row."missing"), 'exception', v_row."exception", 'review', v_row."review", 'basis', v_row."basis", 'deadline', v_row."deadline", 'citation', v_row."citation", 'asOf', v_row."as_of", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
  end if;
  update "better_supabase"."deadlines" x set "state" = 'satisfied', "satisfied_at" = now(), "satisfied_by" = auth.uid(),
    "satisfied_action" = nullif(btrim(satisfy_deadline.action), '')
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional", 'missing', to_jsonb(v_row."missing"), 'exception', v_row."exception", 'review', v_row."review", 'basis', v_row."basis", 'deadline', v_row."deadline", 'citation', v_row."citation", 'asOf', v_row."as_of", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."satisfy_deadline"(uuid, text) from public, anon;
grant execute on function "better_supabase"."satisfy_deadline"(uuid, text) to authenticated, service_role;

-- An organization's deadlines on the subjects the caller may read, soonest
-- first. Security invoker, so the read policy and the subject tables' own
-- policies decide which rows it returns. filters is { subjectType,
-- subjectId, groupKey, period, state, result, provisional, dueBefore, limit }.
create or replace function "better_supabase"."list_deadlines"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_deadlines.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', list_deadlines.tenant, 'deadlines.read'), false))) then
    raise exception 'not allowed to read deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'jurisdiction', y."jurisdiction", 'kind', y."kind", 'groupKey', y."group_key", 'ruleKey', y."rule_key", 'period', y."period", 'ruleVersionId', y."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = y."rule_version_id"), 'facts', y."facts", 'result', y."result", 'dueOn', y."due_on", 'provisional', y."provisional", 'missing', to_jsonb(y."missing"), 'exception', y."exception", 'review', y."review", 'basis', y."basis", 'deadline', y."deadline", 'citation', y."citation", 'asOf', y."as_of", 'state', y."state", 'satisfiedAt', y."satisfied_at", 'satisfiedBy', y."satisfied_by", 'satisfiedAction', y."satisfied_action", 'computedAt', y."computed_at", 'createdAt', y."created_at") order by y."due_on" nulls last, y."created_at")
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = list_deadlines.tenant
        and (not v_filters ? 'subjectType' or z."subject_type" = v_filters ->> 'subjectType')
        and (not v_filters ? 'subjectId' or z."subject_id" = v_filters ->> 'subjectId')
        and (not v_filters ? 'groupKey' or z."group_key" = v_filters ->> 'groupKey')
        and (not v_filters ? 'period' or z."period" = v_filters ->> 'period')
        and (not v_filters ? 'state' or z."state" = v_filters ->> 'state')
        and (not v_filters ? 'result' or z."result" = v_filters ->> 'result')
        and (not v_filters ? 'provisional' or z."provisional" = (v_filters ->> 'provisional')::boolean)
        and (not v_filters ? 'dueBefore' or z."due_on" < (v_filters ->> 'dueBefore')::date)
      order by z."due_on" nulls last, z."created_at"
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_deadlines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_deadlines"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."deadlines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deadlines.read')) and true)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."deadlines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."deadlines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."deadlines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- Deprecated since 0.56.0: use better_supabase.evaluate_deadlines(content, facts, as_of, group_key); removed in 0.58.
create or replace function "better_supabase"."evaluate_deadline_rule"(rule jsonb, facts jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_rule jsonb := case when rule ? 'anchor' then "better_supabase"."deadline_rule_from_v1"(rule) else rule end;
  v_result jsonb;
begin
  v_result := "better_supabase"."evaluate_deadlines"(
    jsonb_build_object('rules', jsonb_build_array(v_rule),
      'groups', jsonb_build_array(jsonb_build_object('key', v_rule -> 'group', 'citation', v_rule -> 'citation'))),
    coalesce(facts, '{}'::jsonb), current_date) -> 0;
  if v_result ->> 'result' = 'due' then
    return jsonb_build_object('status', 'due', 'dueOn', v_result -> 'dueOn');
  end if;
  return jsonb_build_object('status', 'unknown', 'missing', v_result -> 'missing');
end;
$$;
comment on function "better_supabase"."evaluate_deadline_rule"(jsonb, jsonb) is 'deprecated: use evaluate_deadlines';
revoke execute on function "better_supabase"."evaluate_deadline_rule"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."evaluate_deadline_rule"(jsonb, jsonb) to authenticated, service_role;

-- Deprecated since 0.56.0: use better_supabase.compute_deadlines(..., group_key); removed in 0.58.
create or replace function "better_supabase"."compute_deadline"(tenant uuid, subject_type text, subject_id text, jurisdiction text, kind text, rule_key text, facts jsonb default '{}', as_of date default current_date)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."compute_deadlines"(tenant, subject_type, subject_id, jurisdiction, kind, facts, as_of, rule_key) -> 0
$$;
comment on function "better_supabase"."compute_deadline"(uuid, text, text, text, text, text, jsonb, date) is 'deprecated: use compute_deadlines';
revoke execute on function "better_supabase"."compute_deadline"(uuid, text, text, text, text, text, jsonb, date) from public, anon;
grant execute on function "better_supabase"."compute_deadline"(uuid, text, text, text, text, text, jsonb, date) to authenticated, service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_172_deadlines.sql
-- better-supabase module: deadlines
-- @bsb-block-data deadlines
-- @bsb-hash sha256:7ea2732774b4ed46501ce1403ec32652ba8d39b914a294487d9f53853ccc2c11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deadlines', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
