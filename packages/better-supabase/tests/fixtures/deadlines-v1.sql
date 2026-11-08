-- better-supabase module: deadlines
-- @bsb-block deadlines@1 managed
-- @bsb-hash sha256:46db88be123df036fb711e931eb9d978df3ef57a4ce108ffc5389d71147bdfa6
-- Platform-owned rule sets per jurisdiction and kind, versioned and approved once with a content hash and a citation per rule, and the deadlines computed from a subject's facts: due on a date or unknown with the facts still missing, recomputed when facts arrive and satisfied by a recorded action.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deadlines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deadlines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deadlines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deadlines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deadlines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Deadlines: rule sets owned by the platform (no tenant), versioned and approved
-- once, and the deadlines computed from a subject's facts. A rule is data: an
-- anchor fact, an offset, a weekend adjustment, the facts it requires and a
-- citation. A deadline is either due on a date or unknown, naming the facts it
-- still waits for.
create table if not exists "better_supabase"."deadline_rule_sets" (
  "id" uuid primary key default gen_random_uuid(),
  "jurisdiction" text not null check ("jurisdiction" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "title" text check ("title" is null or length("title") <= 200),
  "created_at" timestamptz not null default now(),
  constraint "deadline_rule_sets_key" unique ("jurisdiction", "kind")
);
alter table "better_supabase"."deadline_rule_sets" enable row level security;
revoke all on "better_supabase"."deadline_rule_sets" from public, anon, authenticated;
grant select on "better_supabase"."deadline_rule_sets" to authenticated;
grant all on "better_supabase"."deadline_rule_sets" to service_role;
drop policy if exists deadline_rule_sets_read on "better_supabase"."deadline_rule_sets";
create policy deadline_rule_sets_read on "better_supabase"."deadline_rule_sets"
  for select to authenticated
  using (true);

create table if not exists "better_supabase"."deadline_rule_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "rule_set_id" uuid not null references "better_supabase"."deadline_rule_sets" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "status" text not null default 'draft' check ("status" in ('draft', 'approved')),
  "rules" jsonb not null,
  "content_hash" text,
  "effective_from" date,
  "approved_by" uuid,
  "approved_at" timestamptz,
  "approval_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("rule_set_id", "version"),
  check ("status" = 'draft' or ("content_hash" is not null and "effective_from" is not null and "approved_at" is not null))
);
create index if not exists "deadline_rule_versions_effective_idx" on "better_supabase"."deadline_rule_versions" ("rule_set_id", "effective_from" desc) where "status" = 'approved';
alter table "better_supabase"."deadline_rule_versions" enable row level security;
revoke all on "better_supabase"."deadline_rule_versions" from public, anon, authenticated;
grant select on "better_supabase"."deadline_rule_versions" to authenticated;
grant all on "better_supabase"."deadline_rule_versions" to service_role;
drop policy if exists deadline_rule_versions_read on "better_supabase"."deadline_rule_versions";
create policy deadline_rule_versions_read on "better_supabase"."deadline_rule_versions"
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
drop trigger if exists bsb_deadlines_version_frozen on "better_supabase"."deadline_rule_versions";
create trigger bsb_deadlines_version_frozen
  before update or delete on "better_supabase"."deadline_rule_versions"
  for each row execute function "better_supabase"."deadline_version_frozen"();

create table if not exists "better_supabase"."deadlines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "jurisdiction" text not null,
  "kind" text not null,
  "rule_key" text not null,
  "rule_version_id" uuid not null references "better_supabase"."deadline_rule_versions" ("id") on delete restrict,
  "facts" jsonb not null default '{}'::jsonb,
  "result" text not null check ("result" in ('due', 'unknown')),
  "due_on" date,
  "missing" text[] not null default '{}',
  "citation" jsonb not null,
  "state" text not null default 'pending' check ("state" in ('pending', 'satisfied')),
  "satisfied_at" timestamptz,
  "satisfied_by" uuid,
  "satisfied_action" text check ("satisfied_action" is null or length("satisfied_action") <= 200),
  "computed_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  check (("result" = 'due') = ("due_on" is not null)),
  constraint "deadlines_subject_rule_key" unique ("tenant_id", "subject_type", "subject_id", "rule_key")
);
create index if not exists "deadlines_version_idx" on "better_supabase"."deadlines" ("rule_version_id");
create index if not exists "deadlines_due_idx" on "better_supabase"."deadlines" ("tenant_id", "due_on") where "state" = 'pending';
alter table "better_supabase"."deadlines" enable row level security;
revoke all on "better_supabase"."deadlines" from public, anon, authenticated;
grant select on "better_supabase"."deadlines" to authenticated;
grant all on "better_supabase"."deadlines" to service_role;
drop policy if exists deadlines_read on "better_supabase"."deadlines";
create policy deadlines_read on "better_supabase"."deadlines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deadlines.read')));

-- Evaluates one rule against facts: { status: 'due', dueOn } or
-- { status: 'unknown', missing: [fact names] }. The anchor fact is a date
-- (YYYY-MM-DD). Weekends are Saturday and Sunday; holidays are not modeled.
create or replace function "better_supabase"."evaluate_deadline_rule"(rule jsonb, facts jsonb)
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
        if v_facts ->> v_name !~ '^\s*\d{4}-\d{2}-\d{2}\s*$' then
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
revoke execute on function "better_supabase"."evaluate_deadline_rule"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."evaluate_deadline_rule"(jsonb, jsonb) to authenticated, service_role;

-- The problems of a rule list, as text, empty when it is valid.
create or replace function "better_supabase"."validate_deadline_rules"(rules jsonb)
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
    v_amount := case when (v_rule #>> '{offset,amount}') ~ '^-?\d{1,4}$' then (v_rule #>> '{offset,amount}')::integer end;
    if jsonb_typeof(v_rule -> 'offset') is distinct from 'object'
      or jsonb_typeof(v_rule #> '{offset,amount}') is distinct from 'number'
      or v_amount is null or abs(v_amount) > 3650
      or (v_rule #>> '{offset,unit}') is null or not (v_rule #>> '{offset,unit}') in ('days', 'business_days', 'months') then
      v_issues := v_issues || (v_at || ' needs an offset of a whole amount up to 3650 in days, business_days, months');
    end if;
    if v_rule ? 'adjust' and (jsonb_typeof(v_rule -> 'adjust') is distinct from 'string' or not (v_rule ->> 'adjust') in ('none', 'next_business_day', 'previous_business_day')) then
      v_issues := v_issues || (v_at || ' adjust is none, next_business_day, previous_business_day');
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
revoke execute on function "better_supabase"."validate_deadline_rules"(jsonb) from public, anon;
grant execute on function "better_supabase"."validate_deadline_rules"(jsonb) to authenticated, service_role;

-- Saves the rules of a rule set as a new draft version, creating the rule set
-- on first use. A draft is replaced by the next save until it is approved.
-- Service role only.
create or replace function "better_supabase"."save_rule_version"(jurisdiction text, kind text, rules jsonb, effective_from date default null, title text default null)
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
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role may save rule set versions' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if save_rule_version.jurisdiction is null or save_rule_version.jurisdiction !~ '^[a-z][a-z0-9_-]{0,62}$'
    or save_rule_version.kind is null or save_rule_version.kind !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a rule set has a lower case jurisdiction and kind' using errcode = '22023', hint = 'DEADLINE_RULES_INVALID';
  end if;
  v_issues := "better_supabase"."validate_deadline_rules"(save_rule_version.rules);
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
    update "better_supabase"."deadline_rule_versions" x set "rules" = save_rule_version.rules, "effective_from" = save_rule_version.effective_from
    where x."id" = v_row."id" returning * into v_row;
  else
    insert into "better_supabase"."deadline_rule_versions" ("rule_set_id", "version", "rules", "effective_from")
    values (v_set."id", coalesce((select max(y."version") from "better_supabase"."deadline_rule_versions" y where y."rule_set_id" = v_set."id"), 0) + 1, save_rule_version.rules, save_rule_version.effective_from)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."save_rule_version"(text, text, jsonb, date, text) from public, anon, authenticated;
grant execute on function "better_supabase"."save_rule_version"(text, text, jsonb, date, text) to service_role;

-- Approves a draft version: freezes its rules with a SHA-256 content hash and
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
    return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
  end if;
  v_from := coalesce(approve_rule_version.effective_from, v_row."effective_from");
  if v_from is null then
    raise exception 'an approved version needs the date it applies from' using errcode = '22023', hint = 'DEADLINE_RULES_INVALID';
  end if;
  
  update "better_supabase"."deadline_rule_versions" x set
    "status" = 'approved',
    "effective_from" = v_from,
    "content_hash" = encode(extensions.digest(convert_to(v_row."rules"::text, 'UTF8'), 'sha256'), 'hex'),
    "approved_by" = auth.uid(),
    "approved_at" = now(),
    "approval_id" = approve_rule_version.approval_id
  where x."id" = v_row."id" returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
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
  return jsonb_build_object('id', v_row."id", 'jurisdiction', (select z."jurisdiction" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'kind', (select z."kind" from "better_supabase"."deadline_rule_sets" z where z."id" = v_row."rule_set_id"), 'version', v_row."version", 'status', v_row."status", 'rules', v_row."rules", 'contentHash', v_row."content_hash", 'effectiveFrom', v_row."effective_from", 'approvedBy', v_row."approved_by", 'approvedAt', v_row."approved_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."rule_version_at"(text, text, date) from public, anon;
grant execute on function "better_supabase"."rule_version_at"(text, text, date) to authenticated, service_role;

-- Computes the deadline of one rule for a subject from its facts, with the rule
-- set version that applies on as_of (today by default), and stores it. The
-- result is due on a date or unknown with the facts it waits for. A satisfied
-- deadline is returned unchanged. Needs deadlines.write.
create or replace function "better_supabase"."compute_deadline"(tenant uuid, subject_type text, subject_id text, jurisdiction text, kind text, rule_key text, facts jsonb default '{}', as_of date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_version jsonb;
  v_rule jsonb;
  v_result jsonb;
  v_row "better_supabase"."deadlines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (compute_deadline.tenant is not null and coalesce(better_supabase.can('tenant', compute_deadline.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to compute deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if compute_deadline.subject_type is null or compute_deadline.subject_type !~ '^[a-z][a-z0-9_]{0,62}$'
    or compute_deadline.subject_id is null or length(compute_deadline.subject_id) not between 1 and 200
    or compute_deadline.facts is null or jsonb_typeof(compute_deadline.facts) <> 'object' then
    raise exception 'a deadline needs a subject type, a subject id and facts as an object' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  v_version := "better_supabase"."rule_version_at"(compute_deadline.jurisdiction, compute_deadline.kind, compute_deadline.as_of);
  if v_version is null then
    raise exception 'no approved rule set version applies' using errcode = 'P0002', hint = 'DEADLINE_RULES_NOT_FOUND';
  end if;
  select e.value into v_rule from jsonb_array_elements(v_version -> 'rules') e(value)
  where e.value ->> 'key' = compute_deadline.rule_key;
  if v_rule is null then
    raise exception 'the rule set has no rule with this key' using errcode = 'P0002', hint = 'DEADLINE_RULE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."deadlines" x
  where x."tenant_id" = compute_deadline.tenant and x."subject_type" = compute_deadline.subject_type
    and x."subject_id" = compute_deadline.subject_id and x."rule_key" = compute_deadline.rule_key
  for update;
  if found and v_row."state" = 'satisfied' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'ruleKey', v_row."rule_key", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'missing', to_jsonb(v_row."missing"), 'citation', v_row."citation", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
  end if;
  v_result := "better_supabase"."evaluate_deadline_rule"(v_rule, compute_deadline.facts);
  insert into "better_supabase"."deadlines" ("tenant_id", "subject_type", "subject_id", "jurisdiction", "kind", "rule_key", "rule_version_id", "facts", "result", "due_on", "missing", "citation")
  values (compute_deadline.tenant, compute_deadline.subject_type, compute_deadline.subject_id, compute_deadline.jurisdiction, compute_deadline.kind, compute_deadline.rule_key,
    (v_version ->> 'id')::uuid, compute_deadline.facts, case v_result ->> 'status' when 'due' then 'due' else 'unknown' end,
    nullif(v_result ->> 'dueOn', '')::date,
    coalesce(array(select jsonb_array_elements_text(coalesce(v_result -> 'missing', '[]'::jsonb))), '{}'),
    v_rule -> 'citation')
  on conflict on constraint "deadlines_subject_rule_key" do update set
    "rule_version_id" = excluded."rule_version_id", "facts" = excluded."facts", "result" = excluded."result",
    "due_on" = excluded."due_on", "missing" = excluded."missing", "citation" = excluded."citation",
    "computed_at" = now()
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'ruleKey', v_row."rule_key", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'missing', to_jsonb(v_row."missing"), 'citation', v_row."citation", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."compute_deadline"(uuid, text, text, text, text, text, jsonb, date) from public, anon;
grant execute on function "better_supabase"."compute_deadline"(uuid, text, text, text, text, text, jsonb, date) to authenticated, service_role;

-- Re-evaluates the pending deadlines of a subject after new facts arrived,
-- against the rule set version each one was computed with, and returns how many
-- changed. Runs without a permission check; the facts trigger and
-- recompute_deadlines call it.
create or replace function "better_supabase"."deadline_recompute"(tenant text, subject_type text, subject_id text, p_facts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."deadlines";
  v_version "better_supabase"."deadline_rule_versions";
  v_rule jsonb;
  v_facts jsonb;
  v_result jsonb;
  v_changed integer := 0;
  v_due date;
  v_missing text[];
begin
  for v_row in
    select * from "better_supabase"."deadlines" x
    where x."tenant_id"::text = deadline_recompute.tenant and x."subject_type" = deadline_recompute.subject_type
      and x."subject_id" = deadline_recompute.subject_id and x."state" = 'pending'
    for update
  loop
  select x.* into v_version from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id";
  select e.value into v_rule from jsonb_array_elements(v_version."rules") e(value)
  where e.value ->> 'key' = v_row."rule_key";
  v_facts := v_row."facts" || coalesce(p_facts, '{}'::jsonb);
  v_result := "better_supabase"."evaluate_deadline_rule"(v_rule, v_facts);
    v_due := nullif(v_result ->> 'dueOn', '')::date;
    v_missing := coalesce(array(select jsonb_array_elements_text(coalesce(v_result -> 'missing', '[]'::jsonb))), '{}');
    if v_facts is distinct from v_row."facts" or v_due is distinct from v_row."due_on" or v_missing is distinct from v_row."missing" then
      update "better_supabase"."deadlines" x set "facts" = v_facts,
        "result" = case v_result ->> 'status' when 'due' then 'due' else 'unknown' end,
        "due_on" = v_due, "missing" = v_missing, "computed_at" = now()
      where x."id" = v_row."id" returning * into v_row;
      null;
      v_changed := v_changed + 1;
    end if;
  end loop;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."deadline_recompute"(text, text, text, jsonb) from public, anon, authenticated;

-- Re-evaluates a subject's pending deadlines with extra facts. Needs
-- deadlines.write.
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
  return "better_supabase"."deadline_recompute"(recompute_deadlines.tenant::text, recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.facts);
end;
$$;
revoke execute on function "better_supabase"."recompute_deadlines"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."recompute_deadlines"(uuid, text, text, jsonb) to authenticated, service_role;

-- A trigger function for the table that holds a subject's facts, one row per
-- fact. Attach it with an after insert row trigger and pass the subject type,
-- then the column names for the organization, subject id, fact name and value.
-- A new row recomputes the pending deadlines of its subject.
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

-- Records the action that satisfied a deadline. Needs deadlines.write.
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deadlines.read'), false))) then
    raise exception 'no such deadline' using errcode = 'P0002', hint = 'DEADLINE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deadlines.write'), false))) then
    raise exception 'not allowed to satisfy deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if v_row."state" = 'satisfied' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'ruleKey', v_row."rule_key", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'missing', to_jsonb(v_row."missing"), 'citation', v_row."citation", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
  end if;
  update "better_supabase"."deadlines" x set "state" = 'satisfied', "satisfied_at" = now(), "satisfied_by" = auth.uid(),
    "satisfied_action" = nullif(btrim(satisfy_deadline.action), '')
  where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'ruleKey', v_row."rule_key", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'missing', to_jsonb(v_row."missing"), 'citation', v_row."citation", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."satisfy_deadline"(uuid, text) from public, anon;
grant execute on function "better_supabase"."satisfy_deadline"(uuid, text) to authenticated, service_role;

-- An organization's deadlines, soonest first. filters is { subjectType,
-- subjectId, state, result, dueBefore, limit }.
create or replace function "better_supabase"."list_deadlines"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
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
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'jurisdiction', y."jurisdiction", 'kind', y."kind", 'ruleKey', y."rule_key", 'ruleVersionId', y."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = y."rule_version_id"), 'facts', y."facts", 'result', y."result", 'dueOn', y."due_on", 'missing', to_jsonb(y."missing"), 'citation', y."citation", 'state', y."state", 'satisfiedAt', y."satisfied_at", 'satisfiedBy', y."satisfied_by", 'satisfiedAction', y."satisfied_action", 'computedAt', y."computed_at", 'createdAt', y."created_at") order by y."due_on" nulls last, y."created_at")
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = list_deadlines.tenant
        and (not v_filters ? 'subjectType' or z."subject_type" = v_filters ->> 'subjectType')
        and (not v_filters ? 'subjectId' or z."subject_id" = v_filters ->> 'subjectId')
        and (not v_filters ? 'state' or z."state" = v_filters ->> 'state')
        and (not v_filters ? 'result' or z."result" = v_filters ->> 'result')
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
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."deadlines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deadlines";
create policy bsb_tenant_scope_select on "better_supabase"."deadlines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deadlines.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deadlines";
create policy bsb_tenant_scope_insert on "better_supabase"."deadlines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deadlines";
create policy bsb_tenant_scope_update on "better_supabase"."deadlines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deadlines";
create policy bsb_tenant_scope_delete on "better_supabase"."deadlines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
