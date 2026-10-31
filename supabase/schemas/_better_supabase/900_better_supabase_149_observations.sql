-- better-supabase module: observations
-- @bsb-block observations@1 managed
-- @bsb-hash sha256:eb37ae362aca43899d8a688307bc9f0ac1f9a298a24bbdf4ffe287375cfd4763
-- Typed measurements of a record against definitions with a UCUM unit, a code (LOINC for the shipped vital signs) and valid, reference and critical ranges: a computed flag, critical alerts to the record team's leads, amendments and entered-in-error corrections, idempotent device ingest, series and latest values, and observations mapped from form submissions.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."observation_definitions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."observation_definitions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."observation_definitions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."observation_definitions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."observation_definitions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."observations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."observations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."observations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."observations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."observations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Observations: typed measurements of a record (vital signs, scores, lab
-- values) against definitions with a unit, a code and ranges that flag
-- them, with amendments and entered-in-error corrections kept as history.

create table if not exists "better_supabase"."observation_definitions" (
  "id" uuid primary key default gen_random_uuid(),
  -- Null for a system definition every organization reads.
  "tenant_id" uuid,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "value_type" text not null check ("value_type" in ('number', 'integer', 'boolean', 'code', 'text', 'components')),
  -- A UCUM unit, such as /min, mm[Hg] or Cel.
  "unit" text check ("unit" is null or length("unit") <= 50),
  -- The code that names the observation, such as a LOINC code.
  "code_system" text check ("code_system" is null or length("code_system") <= 200),
  "code" text check ("code" is null or length("code") <= 100),
  -- The parts of a components value, such as systolic and diastolic: an
  -- array of objects with a key, a title, a unit, a code and ranges.
  "components" jsonb check ("components" is null or jsonb_typeof("components") = 'array'),
  "decimals" integer check ("decimals" is null or "decimals" between 0 and 6),
  -- Values outside the valid range are rejected; outside the reference range
  -- they are flagged low or high, at or past a critical bound critical.
  "valid_low" numeric,
  "valid_high" numeric,
  "reference_low" numeric,
  "reference_high" numeric,
  "critical_low" numeric,
  "critical_high" numeric,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("valid_low" is null or "valid_high" is null or "valid_low" <= "valid_high"),
  check ("reference_low" is null or "reference_high" is null or "reference_low" <= "reference_high"),
  check ("critical_low" is null or "critical_high" is null or "critical_low" <= "critical_high"),
  unique nulls not distinct ("tenant_id", "key")
);
alter table "better_supabase"."observation_definitions" enable row level security;
revoke all on "better_supabase"."observation_definitions" from public, anon, authenticated;
grant select on "better_supabase"."observation_definitions" to authenticated;
grant all on "better_supabase"."observation_definitions" to service_role;
drop policy if exists observation_definitions_read on "better_supabase"."observation_definitions";
create policy observation_definitions_read on "better_supabase"."observation_definitions"
  for select to authenticated
  using ("tenant_id" is null or "tenant_id" in (select better_supabase.tenant_ids_with('observations.read')) or "tenant_id" in (select better_supabase.member_organization_ids()));

create table if not exists "better_supabase"."observations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "definition_id" uuid not null references "better_supabase"."observation_definitions" ("id") on delete restrict,
  "subject_type" text not null check (length("subject_type") between 1 and 100),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "observed_at" timestamptz not null default now(),
  -- One of these holds the value, by the definition's value type; a
  -- boolean is stored as true or false in the code column.
  "value_number" numeric,
  "value_text" text check ("value_text" is null or length("value_text") <= 4000),
  "value_code" text check ("value_code" is null or length("value_code") <= 200),
  "components" jsonb check ("components" is null or jsonb_typeof("components") = 'object'),
  "flag" text not null default 'normal' check ("flag" in ('normal', 'low', 'high', 'critical_low', 'critical_high')),
  "status" text not null default 'final' check ("status" in ('final', 'amended', 'entered_in_error')),
  -- The observation this one corrects.
  "replaces_id" uuid references "better_supabase"."observations" ("id") on delete set null,
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "method" text check ("method" is null or length("method") <= 200),
  "device" text check ("device" is null or length("device") <= 200),
  "source" text not null default 'manual' check ("source" in ('manual', 'form', 'device', 'import')),
  -- The id a device or an import gives the reading, so ingesting it again
  -- changes nothing.
  "external_id" text check ("external_id" is null or length("external_id") between 1 and 200),
  "submission_id" uuid references "better_supabase"."form_submissions" ("id") on delete set null,
  "performer_id" uuid,
  "note" text check ("note" is null or length("note") <= 4000),
  "created_at" timestamptz not null default now()
);
create index if not exists "observations_series_idx" on "better_supabase"."observations" ("subject_type", "subject_id", "definition_id", "observed_at" desc);
create index if not exists "observations_definition_idx" on "better_supabase"."observations" ("definition_id");
create index if not exists "observations_tenant_idx" on "better_supabase"."observations" ("tenant_id", "observed_at" desc);
create index if not exists "observations_replaces_idx" on "better_supabase"."observations" ("replaces_id") where "replaces_id" is not null;
create index if not exists "observations_submission_idx" on "better_supabase"."observations" ("submission_id") where "submission_id" is not null;
create unique index if not exists "observations_external_key" on "better_supabase"."observations" ("tenant_id", "external_id") where "external_id" is not null;
alter table "better_supabase"."observations" enable row level security;
revoke all on "better_supabase"."observations" from public, anon, authenticated;
grant select on "better_supabase"."observations" to authenticated;
grant all on "better_supabase"."observations" to service_role;
drop policy if exists observations_read on "better_supabase"."observations";
create policy observations_read on "better_supabase"."observations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('observations.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

-- The flag of a value against a range: critical at or past a critical
-- bound, low or high outside the reference range, else normal.
create or replace function "better_supabase"."observation_flag"(value numeric, reference_low numeric, reference_high numeric, critical_low numeric, critical_high numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when value is null then 'normal'
    when critical_low is not null and value <= critical_low then 'critical_low'
    when critical_high is not null and value >= critical_high then 'critical_high'
    when reference_low is not null and value < reference_low then 'low'
    when reference_high is not null and value > reference_high then 'high'
    else 'normal'
  end
$$;
revoke execute on function "better_supabase"."observation_flag"(numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- The definition a key names for an organization: its own, else the system
-- one.
create or replace function "better_supabase"."observation_definition_id"(p_tenant uuid, p_key text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select d."id" into v_id from "better_supabase"."observation_definitions" d
  where d."key" = p_key and (d."tenant_id" = p_tenant or d."tenant_id" is null)
  order by d."tenant_id" nulls last
  limit 1;
  if v_id is null then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."observation_definition_id"(uuid, text) from public, anon, authenticated;

-- Checks a value against its definition, computes the flag and inserts
-- the observation, with its events and the critical alert. Callers check
-- the caller and the record first.
create or replace function "better_supabase"."observation_insert"(p_tenant uuid, p_definition uuid, p_subject_type text, p_subject_id text, p_value jsonb, p_observed_at timestamptz, p_details jsonb, p_source text, p_external_id text, p_submission uuid, p_performer uuid, p_replaces uuid, p_fields jsonb)
returns "better_supabase"."observations"
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_row "better_supabase"."observations"%rowtype;
  v_at timestamptz := coalesce(p_observed_at, now());
  v_number numeric;
  v_text text;
  v_code text;
  v_components jsonb;
  v_flag text := 'normal';
  v_component jsonb;
  v_key text;
  v_part numeric;
  v_part_flag text;
  v_recipients jsonb;
  v_claims text;
begin
  select * into v_def from "better_supabase"."observation_definitions" d where d."id" = p_definition;
  if not found then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  if v_def."archived_at" is not null then
    raise exception 'the observation definition is archived' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_ARCHIVED';
  end if;
  if v_at > now() + interval '5 minutes' then
    raise exception 'observed_at is in the future' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if p_details is not null and jsonb_typeof(p_details) <> 'object' then
    raise exception 'details is an object of method, device and note' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    raise exception 'an observation needs a value' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
  end if;
  case v_def."value_type"
    when 'number', 'integer' then
      if jsonb_typeof(p_value) <> 'number' then
        raise exception '%s takes a number', v_def."key" using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_number := (p_value #>> '{}')::numeric;
      if v_def."value_type" = 'integer' and v_number <> trunc(v_number) then
        raise exception 'the value is a whole number' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      if v_def."decimals" is not null then
        v_number := round(v_number, v_def."decimals");
      end if;
      if v_number < v_def."valid_low" or v_number > v_def."valid_high" then
        raise exception 'the value is outside the definition''s valid range' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_flag := "better_supabase"."observation_flag"(v_number, v_def."reference_low", v_def."reference_high", v_def."critical_low", v_def."critical_high");
    when 'boolean' then
      if jsonb_typeof(p_value) <> 'boolean' then
        raise exception 'the value is true or false' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_code := p_value #>> '{}';
    when 'code' then
      v_code := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_code is null or length(v_code) > 200 then
        raise exception 'the value is a code of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
    when 'text' then
      v_text := nullif(trim(p_value #>> '{}'), '');
      if jsonb_typeof(p_value) <> 'string' or v_text is null or length(v_text) > 4000 then
        raise exception 'the value is a text of at most 4000 characters' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
    else
      if jsonb_typeof(p_value) <> 'object' then
        raise exception 'the value is an object of components' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      if exists (
        select 1 from jsonb_object_keys(p_value) k
        where not exists (select 1 from jsonb_array_elements(coalesce(v_def."components", '[]'::jsonb)) c where c ->> 'key' = k)
      ) then
        raise exception 'the value names a component the definition doesn''t have' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
      v_components := '{}'::jsonb;
      for v_component in select c from jsonb_array_elements(coalesce(v_def."components", '[]'::jsonb)) c loop
        v_key := v_component ->> 'key';
        if not (p_value ? v_key) or jsonb_typeof(p_value -> v_key) = 'null' then
          if coalesce((v_component ->> 'optional')::boolean, false) then
            continue;
          end if;
          raise exception 'the value needs the %s component', v_key using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        if jsonb_typeof(p_value -> v_key) <> 'number' then
          raise exception 'each component is a number' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        v_part := (p_value ->> v_key)::numeric;
        if v_component ? 'decimals' then
          v_part := round(v_part, (v_component ->> 'decimals')::integer);
        elsif v_def."decimals" is not null then
          v_part := round(v_part, v_def."decimals");
        end if;
        if v_part < (v_component ->> 'validLow')::numeric or v_part > (v_component ->> 'validHigh')::numeric then
          raise exception 'a component is outside its valid range' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
        end if;
        v_part_flag := "better_supabase"."observation_flag"(v_part, (v_component ->> 'referenceLow')::numeric, (v_component ->> 'referenceHigh')::numeric, (v_component ->> 'criticalLow')::numeric, (v_component ->> 'criticalHigh')::numeric);
        if (case v_part_flag when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end) > (case v_flag when 'critical_low' then 2 when 'critical_high' then 2 when 'low' then 1 when 'high' then 1 else 0 end) then
          v_flag := v_part_flag;
        end if;
        v_components := v_components || jsonb_build_object(v_key, v_part);
      end loop;
      if v_components = '{}'::jsonb then
        raise exception 'the value needs at least one component' using errcode = '22023', hint = 'OBSERVATION_VALUE_INVALID';
      end if;
  end case;
  if p_replaces is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_record"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using p_tenant, p_subject_type, p_subject_id, v_def."key";
    end if;
  end;
  end if;
  insert into "better_supabase"."observations" ("tenant_id", "definition_id", "subject_type", "subject_id", "observed_at", "value_number", "value_text", "value_code", "components", "flag", "replaces_id", "method", "device", "source", "external_id", "submission_id", "performer_id", "note")
  values (p_tenant, v_def."id", p_subject_type, p_subject_id, v_at, v_number, v_text, v_code, v_components, v_flag, p_replaces, left(nullif(trim(p_details ->> 'method'), ''), 200), left(nullif(trim(p_details ->> 'device'), ''), 200), p_source, p_external_id, p_submission, p_performer, left(nullif(trim(p_details ->> 'note'), ''), 4000))
  returning * into v_row;
  if p_replaces is null then
    perform "better_supabase".emit_event('observation.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag", 'source', v_row."source"), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.recorded',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag", 'source', v_row."source")
  );
  end if;
  if v_row."flag" in ('critical_low', 'critical_high') then
    perform "better_supabase".emit_event('observation.critical_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'flag', v_row."flag"), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
    select coalesce(jsonb_agg(distinct m."user_id"), '[]'::jsonb) into v_recipients
    from "better_supabase"."subject_members" m
    where m."subject_type" = v_row."subject_type"
      and m."subject_id" = v_row."subject_id"
      and m."tenant_id"::text = v_row."tenant_id"::text
      and m."role" = 'lead'
      and m."user_id" is not null
      and (m."starts_on" is null or m."starts_on" <= current_date)
      and (m."ends_on" is null or m."ends_on" >= current_date);
    if jsonb_array_length(v_recipients) > 0 then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'observation.critical_recorded',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', v_row."subject_type",
        'subject_id', v_row."subject_id",
        'summary', v_def."title" || ' is ' || replace(v_row."flag", '_', ' '),
        'recipients', v_recipients,
        'key', 'observation.critical_recorded:' || v_row."id"::text,
        'data', jsonb_build_object('observationId', v_row."id", 'definitionKey', v_def."key", 'flag', v_row."flag")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
  end if;
  if p_replaces is null then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."observation_insert"(uuid, uuid, text, text, jsonb, timestamptz, jsonb, text, text, uuid, uuid, uuid, jsonb) from public, anon, authenticated;

-- Creates or changes an organization's definition with this key; a system
-- definition with the same key stays, and the organization's wins. Only
-- the service role saves system definitions (tenant null).
create or replace function "better_supabase"."save_observation_definition"(tenant uuid, key text, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."observation_definitions"%rowtype;
  v_old "better_supabase"."observation_definitions"%rowtype;
  v_definition jsonb := coalesce(save_observation_definition.definition, '{}'::jsonb);
  v_title text;
  v_type text;
  v_components jsonb;
  v_component jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_observation_definition.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role saves system definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_observation_definition.tenant, 'observations.manage'), false)) then
    raise exception 'not allowed to manage observation definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if save_observation_definition.key is null or save_observation_definition.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'the key takes lowercase letters, digits and underscores, starting with a letter' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if jsonb_typeof(v_definition) <> 'object' then
    raise exception 'definition is an object' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  v_title := nullif(trim(v_definition ->> 'title'), '');
  if v_title is null or length(v_title) > 200 then
    raise exception 'a definition needs a title of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  v_type := v_definition ->> 'valueType';
  if v_type is null or v_type not in ('number', 'integer', 'boolean', 'code', 'text', 'components') then
    raise exception 'valueType is one of number, integer, boolean, code, text, components' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'unit' and (jsonb_typeof(v_definition -> 'unit') not in ('string', 'null') or length(v_definition ->> 'unit') > 50) then
    raise exception 'unit is a UCUM unit of at most 50 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'codeSystem' and (jsonb_typeof(v_definition -> 'codeSystem') not in ('string', 'null') or length(v_definition ->> 'codeSystem') > 200) then
    raise exception 'codeSystem is a text of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'code' and (jsonb_typeof(v_definition -> 'code') not in ('string', 'null') or length(v_definition ->> 'code') > 100) then
    raise exception 'code is a text of at most 100 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'decimals' and jsonb_typeof(v_definition -> 'decimals') <> 'null' and (jsonb_typeof(v_definition -> 'decimals') <> 'number' or (v_definition ->> 'decimals')::numeric not in (0, 1, 2, 3, 4, 5, 6)) then
    raise exception 'decimals is a whole number from 0 to 6' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'validLow' and jsonb_typeof(v_definition -> 'validLow') not in ('number', 'null') then
    raise exception 'the definition''s validLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'validHigh' and jsonb_typeof(v_definition -> 'validHigh') not in ('number', 'null') then
    raise exception 'the definition''s validHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'referenceLow' and jsonb_typeof(v_definition -> 'referenceLow') not in ('number', 'null') then
    raise exception 'the definition''s referenceLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'referenceHigh' and jsonb_typeof(v_definition -> 'referenceHigh') not in ('number', 'null') then
    raise exception 'the definition''s referenceHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'criticalLow' and jsonb_typeof(v_definition -> 'criticalLow') not in ('number', 'null') then
    raise exception 'the definition''s criticalLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_definition ? 'criticalHigh' and jsonb_typeof(v_definition -> 'criticalHigh') not in ('number', 'null') then
    raise exception 'the definition''s criticalHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_definition ->> 'validLow')::numeric > (v_definition ->> 'validHigh')::numeric then
    raise exception 'the definition''s validLow is at most validHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_definition ->> 'referenceLow')::numeric > (v_definition ->> 'referenceHigh')::numeric then
    raise exception 'the definition''s referenceLow is at most referenceHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_definition ->> 'criticalLow')::numeric > (v_definition ->> 'criticalHigh')::numeric then
    raise exception 'the definition''s criticalLow is at most criticalHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  v_components := case when jsonb_typeof(v_definition -> 'components') = 'null' then null else v_definition -> 'components' end;
  if v_type = 'components' then
    if jsonb_typeof(v_components) is distinct from 'array' or jsonb_array_length(v_components) not between 1 and 20 then
      raise exception 'a components definition has 1 to 20 components' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
    end if;
    if (select count(distinct c ->> 'key') from jsonb_array_elements(v_components) c) <> jsonb_array_length(v_components) then
      raise exception 'component keys are unique' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
    end if;
    for v_component in select c from jsonb_array_elements(v_components) c loop
      if jsonb_typeof(v_component) <> 'object' or coalesce(v_component ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,62}$' then
        raise exception 'each component has a key of lowercase letters, digits and underscores' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if nullif(trim(v_component ->> 'title'), '') is null or length(v_component ->> 'title') > 200 then
        raise exception 'each component has a title of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if v_component ? 'unit' and (jsonb_typeof(v_component -> 'unit') not in ('string', 'null') or length(v_component ->> 'unit') > 50) then
    raise exception 'a component unit is at most 50 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
      if v_component ? 'code' and (jsonb_typeof(v_component -> 'code') not in ('string', 'null') or length(v_component ->> 'code') > 100) then
    raise exception 'a component code is at most 100 characters' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
      if v_component ? 'decimals' and (jsonb_typeof(v_component -> 'decimals') <> 'number' or (v_component ->> 'decimals')::numeric not in (0, 1, 2, 3, 4, 5, 6)) then
        raise exception 'a component''s decimals is a whole number from 0 to 6' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if v_component ? 'optional' and jsonb_typeof(v_component -> 'optional') <> 'boolean' then
        raise exception 'a component''s optional is true or false' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
      end if;
      if v_component ? 'validLow' and jsonb_typeof(v_component -> 'validLow') not in ('number', 'null') then
    raise exception 'a component''s validLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'validHigh' and jsonb_typeof(v_component -> 'validHigh') not in ('number', 'null') then
    raise exception 'a component''s validHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'referenceLow' and jsonb_typeof(v_component -> 'referenceLow') not in ('number', 'null') then
    raise exception 'a component''s referenceLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'referenceHigh' and jsonb_typeof(v_component -> 'referenceHigh') not in ('number', 'null') then
    raise exception 'a component''s referenceHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'criticalLow' and jsonb_typeof(v_component -> 'criticalLow') not in ('number', 'null') then
    raise exception 'a component''s criticalLow is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if v_component ? 'criticalHigh' and jsonb_typeof(v_component -> 'criticalHigh') not in ('number', 'null') then
    raise exception 'a component''s criticalHigh is a number' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_component ->> 'validLow')::numeric > (v_component ->> 'validHigh')::numeric then
    raise exception 'a component''s validLow is at most validHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_component ->> 'referenceLow')::numeric > (v_component ->> 'referenceHigh')::numeric then
    raise exception 'a component''s referenceLow is at most referenceHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  if (v_component ->> 'criticalLow')::numeric > (v_component ->> 'criticalHigh')::numeric then
    raise exception 'a component''s criticalLow is at most criticalHigh' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
    end loop;
  elsif v_components is not null then
    raise exception 'only a components definition has components' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  select * into v_old from "better_supabase"."observation_definitions" x
  where x."tenant_id" is not distinct from save_observation_definition.tenant and x."key" = save_observation_definition.key;
  if found and v_old."value_type" <> v_type and exists (select 1 from "better_supabase"."observations" x where x."definition_id" = v_old."id") then
    raise exception 'the value type can''t change once observations use the definition' using errcode = '22023', hint = 'OBSERVATION_DEFINITION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_definition_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_observation_definition.tenant, save_observation_definition.key;
    end if;
  end;
  insert into "better_supabase"."observation_definitions" ("tenant_id", "key", "title", "value_type", "unit", "code_system", "code", "components", "decimals", "valid_low", "valid_high", "reference_low", "reference_high", "critical_low", "critical_high")
  values (save_observation_definition.tenant, save_observation_definition.key, v_title, v_type, nullif(trim(v_definition ->> 'unit'), ''), nullif(trim(v_definition ->> 'codeSystem'), ''), nullif(trim(v_definition ->> 'code'), ''), v_components, (v_definition ->> 'decimals')::integer, (v_definition ->> 'validLow')::numeric, (v_definition ->> 'validHigh')::numeric, (v_definition ->> 'referenceLow')::numeric, (v_definition ->> 'referenceHigh')::numeric, (v_definition ->> 'criticalLow')::numeric, (v_definition ->> 'criticalHigh')::numeric)
  on conflict ("tenant_id", "key") do update set
      "title" = excluded."title",
      "value_type" = excluded."value_type",
      "unit" = excluded."unit",
      "code_system" = excluded."code_system",
      "code" = excluded."code",
      "components" = excluded."components",
      "decimals" = excluded."decimals",
      "valid_low" = excluded."valid_low",
      "valid_high" = excluded."valid_high",
      "reference_low" = excluded."reference_low",
      "reference_high" = excluded."reference_high",
      "critical_low" = excluded."critical_low",
      "critical_high" = excluded."critical_high",
      "archived_at" = null,
      "updated_at" = now()
  returning * into v_row;
  if v_old."id" is null then
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.created', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.created',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  else
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.updated',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_definition_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'system', v_row."tenant_id" is null, 'key', v_row."key", 'title', v_row."title", 'valueType', v_row."value_type", 'unit', v_row."unit", 'codeSystem', v_row."code_system", 'code', v_row."code", 'components', coalesce(v_row."components", '[]'::jsonb), 'decimals', v_row."decimals", 'validLow', v_row."valid_low", 'validHigh', v_row."valid_high", 'referenceLow', v_row."reference_low", 'referenceHigh', v_row."reference_high", 'criticalLow', v_row."critical_low", 'criticalHigh', v_row."critical_high", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_observation_definition"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_observation_definition"(uuid, text, jsonb) to authenticated, service_role;

-- Archives a definition: it takes no new observations, and the ones it
-- has stay.
create or replace function "better_supabase"."archive_observation_definition"(definition_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."observation_definitions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."observation_definitions" x where x."id" = archive_observation_definition.definition_id;
  if not found then
    raise exception 'observation definition not found' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
  end if;
  if v_row."tenant_id" is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'only the service role archives system definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'observations.manage'), false)) then
    raise exception 'not allowed to manage observation definitions' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."observation_definitions" x set "archived_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('observation_definition.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title"), 'observation-definitions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation_definition.updated',
    category => 'configuration',
    target_type => 'observation_definition',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'Observation definition archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'definitionId', v_row."id", 'key', v_row."key", 'title', v_row."title")
  );
  end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'system', v_row."tenant_id" is null, 'key', v_row."key", 'title', v_row."title", 'valueType', v_row."value_type", 'unit', v_row."unit", 'codeSystem', v_row."code_system", 'code', v_row."code", 'components', coalesce(v_row."components", '[]'::jsonb), 'decimals', v_row."decimals", 'validLow', v_row."valid_low", 'validHigh', v_row."valid_high", 'referenceLow', v_row."reference_low", 'referenceHigh', v_row."reference_high", 'criticalLow', v_row."critical_low", 'criticalHigh', v_row."critical_high", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_observation_definition"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_observation_definition"(uuid) to authenticated, service_role;

-- Records one observation of a record by its definition key. value is a
-- number, true or false, a string, or an object of components; details
-- takes method, device and note.
drop function if exists "better_supabase"."record_observation"(uuid, text, text, text, jsonb, timestamptz, jsonb, jsonb);
create or replace function "better_supabase"."record_observation"(tenant uuid, subject_type text, subject_id text, definition_key text, value jsonb, observed_at timestamptz default null, details jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_observation.tenant, 'observations.record'), false)) then
    raise exception 'not allowed to record observations' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if not (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case record_observation.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (record_observation.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (record_observation.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (record_observation.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_observation.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_observation.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_observation.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (record_observation.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (record_observation.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (record_observation.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_observation.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_observation.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (record_observation.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_observation.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_observation.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (record_observation.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_observation.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (record_observation.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (record_observation.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (record_observation.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (record_observation.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (record_observation.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (record_observation.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (record_observation.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (record_observation.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (record_observation.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (record_observation.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (record_observation.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (record_observation.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (record_observation.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (record_observation.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (record_observation.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (record_observation.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (record_observation.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (record_observation.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (record_observation.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (record_observation.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (record_observation.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (record_observation.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (record_observation.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (record_observation.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_observation.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_observation.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_observation.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_observation.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (record_observation.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_observation.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_observation.subject_id)::uuid)
      else null::text
    end) = record_observation.tenant::text, false) else (case record_observation.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_observation.subject_id)::uuid and s."tenant_id"::text = record_observation.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_observation.subject_id)::uuid and s."organization_id"::text = record_observation.tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_observation.subject_type, record_observation.subject_id, 'read')) end) then
    raise exception 'the record isn''t in this organization, or you can''t read it' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."observation_insert"(record_observation.tenant, "better_supabase"."observation_definition_id"(record_observation.tenant, record_observation.definition_key), record_observation.subject_type, record_observation.subject_id, record_observation.value, record_observation.observed_at, record_observation.details, 'manual', null, null, (select auth.uid()), null, null);
  select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_observation"(uuid, text, text, text, jsonb, timestamptz, jsonb) from public, anon;
grant execute on function "better_supabase"."record_observation"(uuid, text, text, text, jsonb, timestamptz, jsonb) to authenticated, service_role;

-- Records several observations at once (a round of vitals), all or none.
-- Each item takes subjectType, subjectId, definitionKey, value and
-- optionally observedAt, details and fields.
create or replace function "better_supabase"."record_observations"(tenant uuid, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_observations.tenant, 'observations.record'), false)) then
    raise exception 'not allowed to record observations' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if jsonb_typeof(record_observations.items) is distinct from 'array' or jsonb_array_length(record_observations.items) not between 1 and 500 then
    raise exception 'items is an array of 1 to 500 observations' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  for v_item in select i from jsonb_array_elements(record_observations.items) i loop
    if jsonb_typeof(v_item) <> 'object' or nullif(v_item ->> 'subjectType', '') is null or nullif(v_item ->> 'subjectId', '') is null or nullif(v_item ->> 'definitionKey', '') is null then
      raise exception 'each item has a subjectType, a subjectId, a definitionKey and a value' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    if not (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_item ->> 'subjectType'
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      else null::text
    end) = record_observations.tenant::text, false) else (case v_item ->> 'subjectType'
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = record_observations.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = record_observations.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_item ->> 'subjectType', v_item ->> 'subjectId', 'read')) end) then
      raise exception 'the record isn''t in this organization, or you can''t read it' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
    select * into v_row from "better_supabase"."observation_insert"(record_observations.tenant, "better_supabase"."observation_definition_id"(record_observations.tenant, v_item ->> 'definitionKey'), v_item ->> 'subjectType', v_item ->> 'subjectId', v_item -> 'value', (v_item ->> 'observedAt')::timestamptz, v_item -> 'details', 'manual', null, null, (select auth.uid()), null, v_item -> 'fields');
    select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
    v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."record_observations"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_observations"(uuid, jsonb) to authenticated, service_role;

-- Ingests readings from a device or an import, as the service role. Each
-- item also takes externalId, which makes it idempotent, and source
-- (device, the default, or import). Returns {inserted, skipped, ids}.
create or replace function "better_supabase"."ingest_observations"(tenant uuid, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_row "better_supabase"."observations"%rowtype;
  v_external text;
  v_source text;
  v_ids jsonb := '[]'::jsonb;
  v_skipped integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role ingests observations' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if jsonb_typeof(ingest_observations.items) is distinct from 'array' or jsonb_array_length(ingest_observations.items) not between 1 and 500 then
    raise exception 'items is an array of 1 to 500 observations' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  for v_item in select i from jsonb_array_elements(ingest_observations.items) i loop
    if jsonb_typeof(v_item) <> 'object' or nullif(v_item ->> 'subjectType', '') is null or nullif(v_item ->> 'subjectId', '') is null or nullif(v_item ->> 'definitionKey', '') is null then
      raise exception 'each item has a subjectType, a subjectId, a definitionKey and a value' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null or length(v_external) > 200 then
      raise exception 'each ingested item has an externalId of at most 200 characters' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    v_source := coalesce(v_item ->> 'source', 'device');
    if v_source not in ('device', 'import') then
      raise exception 'source is device or import' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    if not (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_item ->> 'subjectType'
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid)
      else null::text
    end) = ingest_observations.tenant::text, false) else (case v_item ->> 'subjectType'
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_item ->> 'subjectId')::uuid and s."tenant_id"::text = ingest_observations.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_item ->> 'subjectId')::uuid and s."organization_id"::text = ingest_observations.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_item ->> 'subjectType', v_item ->> 'subjectId', 'read')) end) then
      raise exception 'the record isn''t in this organization' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_observations_ingest:' || ingest_observations.tenant::text || ':' || v_external, 0));
    if exists (select 1 from "better_supabase"."observations" x where x."tenant_id" = ingest_observations.tenant and x."external_id" = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    select * into v_row from "better_supabase"."observation_insert"(ingest_observations.tenant, "better_supabase"."observation_definition_id"(ingest_observations.tenant, v_item ->> 'definitionKey'), v_item ->> 'subjectType', v_item ->> 'subjectId', v_item -> 'value', (v_item ->> 'observedAt')::timestamptz, v_item -> 'details', v_source, v_external, null, null, null, v_item -> 'fields');
    v_ids := v_ids || jsonb_build_array(v_row."id");
  end loop;
  return jsonb_build_object('inserted', jsonb_array_length(v_ids), 'skipped', v_skipped, 'ids', v_ids);
end;
$$;
revoke execute on function "better_supabase"."ingest_observations"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_observations"(uuid, jsonb) to service_role;

-- Corrects a final observation: a new observation replaces it (replacesId)
-- and the old one becomes amended with the reason. changes takes value,
-- observedAt, method, device, note and fields; what it leaves out stays.
create or replace function "better_supabase"."amend_observation"(observation_id uuid, changes jsonb, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."observations"%rowtype;
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_changes jsonb := coalesce(amend_observation.changes, '{}'::jsonb);
  v_reason text := nullif(trim(amend_observation.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_old from "better_supabase"."observations" x where x."id" = amend_observation.observation_id for update;
  if not found then
    raise exception 'observation not found' using errcode = 'P0002', hint = 'OBSERVATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'observations.record'), false)) and (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_old."subject_type"
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_old."subject_id")::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_old."subject_id")::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_old."subject_id")::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_old."subject_id")::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_old."subject_id")::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_old."subject_id")::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_old."subject_id")::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_old."subject_id")::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (v_old."subject_id")::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_old."subject_id")::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_old."subject_id")::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_old."subject_id")::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_old."subject_id")::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_old."subject_id")::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_old."subject_id")::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_old."subject_id")::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_old."subject_id")::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_old."subject_id")::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_old."subject_id")::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_old."subject_id")::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_old."subject_id")::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (v_old."subject_id")::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_old."subject_id")::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_old."subject_id")::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_old."subject_id")::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_old."subject_id")::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_old."subject_id")::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_old."subject_id")::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_old."subject_id")::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (v_old."subject_id")::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_old."subject_id")::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_old."subject_id")::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (v_old."subject_id")::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (v_old."subject_id")::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (v_old."subject_id")::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (v_old."subject_id")::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_old."subject_id")::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (v_old."subject_id")::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (v_old."subject_id")::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (v_old."subject_id")::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (v_old."subject_id")::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_old."subject_id")::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_old."subject_id")::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_old."subject_id")::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_old."subject_id")::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_old."subject_id")::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_old."subject_id")::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_old."subject_id")::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_old."subject_id")::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_old."subject_id")::uuid)
      else null::text
    end) = v_old."tenant_id"::text, false) else (case v_old."subject_type"
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_old."subject_id")::uuid and s."tenant_id"::text = v_old."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_old."subject_id")::uuid and s."organization_id"::text = v_old."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_old."subject_type", v_old."subject_id", 'read')) end)) then
    raise exception 'not allowed to amend this observation' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  if v_old."status" <> 'final' then
    raise exception 'only a final observation can be amended' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'an amendment needs a reason of at most 2000 characters' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if jsonb_typeof(v_changes) <> 'object' then
    raise exception 'changes is an object' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_old."definition_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_amend"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_old."id";
    end if;
  end;
  update "better_supabase"."observations" x set "status" = 'amended', "reason" = v_reason
  where x."id" = v_old."id";
  select * into v_row from "better_supabase"."observation_insert"(v_old."tenant_id", v_old."definition_id", v_old."subject_type", v_old."subject_id", coalesce(v_changes -> 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_old."value_code" = 'true')
      when 'code' then to_jsonb(v_old."value_code")
      when 'text' then to_jsonb(v_old."value_text")
      when 'components' then v_old."components"
      else to_jsonb(v_old."value_number")
    end), coalesce((v_changes ->> 'observedAt')::timestamptz, v_old."observed_at"), jsonb_strip_nulls(jsonb_build_object('method', v_old."method", 'device', v_old."device", 'note', v_old."note")) || (v_changes - 'value' - 'observedAt' - 'fields'), v_old."source", null, v_old."submission_id", (select auth.uid()), v_old."id", to_jsonb(v_old) || coalesce(v_changes -> 'fields', '{}'::jsonb));
  perform "better_supabase".emit_event('observation.amended', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'replacesId', v_old."id", 'reason', v_reason), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.amended',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation amended',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'replacesId', v_old."id", 'reason', v_reason)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_amend"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."amend_observation"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."amend_observation"(uuid, jsonb, text) to authenticated, service_role;

-- Marks a final observation entered in error, with the reason. It leaves
-- series and the latest values; marking it again changes nothing.
create or replace function "better_supabase"."mark_observation_error"(observation_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_reason text := nullif(trim(mark_observation_error.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."observations" x where x."id" = mark_observation_error.observation_id for update;
  if not found then
    raise exception 'observation not found' using errcode = 'P0002', hint = 'OBSERVATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'observations.record'), false)) and (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_row."subject_type"
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (v_row."subject_id")::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (v_row."subject_id")::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (v_row."subject_id")::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_row."subject_id")::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_row."subject_id")::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (v_row."subject_id")::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (v_row."subject_id")::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (v_row."subject_id")::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (v_row."subject_id")::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (v_row."subject_id")::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (v_row."subject_id")::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (v_row."subject_id")::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (v_row."subject_id")::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_row."subject_id")::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_row."subject_id")::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid)
      else null::text
    end) = v_row."tenant_id"::text, false) else (case v_row."subject_type"
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read')) end)) then
    raise exception 'not allowed to correct this observation' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
  if v_row."status" = 'entered_in_error' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
  end if;
  if v_row."status" <> 'final' then
    raise exception 'only a final observation can be marked entered in error' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'marking an observation entered in error needs a reason of at most 2000 characters' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_observation_mark_error"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."observations" x set "status" = 'entered_in_error', "reason" = v_reason
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('observation.error_marked', jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'reason', v_reason), 'observations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/observations');
  perform better_supabase.audit_event(
    event_type => 'observation.error_marked',
    category => 'data',
    target_type => 'observation',
    record_id => v_row."id"::text,
    target_label => v_def."title",
    summary => 'Observation marked entered in error',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'observationId', v_row."id", 'definitionKey', v_def."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'reason', v_reason)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_observation_mark_error"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."mark_observation_error"(uuid, text) from public, anon;
grant execute on function "better_supabase"."mark_observation_error"(uuid, text) to authenticated, service_role;

-- An organization's definitions with the system ones it doesn't override,
-- by title.
create or replace function "better_supabase"."list_observation_definitions"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."title", x."key"), '[]'::jsonb)
  from "better_supabase"."observation_definitions" x
  where (
      x."tenant_id" = list_observation_definitions.tenant
      or (x."tenant_id" is null and not exists (
        select 1 from "better_supabase"."observation_definitions" y
        where y."tenant_id" = list_observation_definitions.tenant and y."key" = x."key"
      ))
    )
    and (coalesce(list_observation_definitions.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_observation_definitions"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_observation_definitions"(uuid, boolean) to authenticated, service_role;

-- A record's observations, the latest first: the final ones, or with
-- include_all the amended and entered-in-error ones too.
create or replace function "better_supabase"."list_observations"(subject_type text, subject_id text, definition_key text default null, include_all boolean default false, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.item order by r.at desc, r.created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") as item, x."observed_at" as at, x."created_at" as created
    from "better_supabase"."observations" x
    join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
    where x."subject_type" = list_observations.subject_type
      and x."subject_id" = list_observations.subject_id
      and (list_observations.definition_key is null or y."key" = list_observations.definition_key)
      and (coalesce(list_observations.include_all, false) or x."status" = 'final')
    order by x."observed_at" desc, x."created_at" desc
    limit least(greatest(coalesce(list_observations.max_rows, 100), 1), 1000)
  ) r
$$;
revoke execute on function "better_supabase"."list_observations"(text, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_observations"(text, text, text, boolean, integer) to authenticated, service_role;

-- The final observations of one definition key for a record between since
-- and until (until excluded), oldest first. Without a bucket each point is
-- {id, observedAt, value, flag}; with hour, day, week or month (UTC) each
-- bucket has count, min, max and avg, per component for components.
create or replace function "better_supabase"."observation_series"(subject_type text, subject_id text, definition_key text, since timestamptz default null, until timestamptz default null, bucket text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if observation_series.bucket is not null and observation_series.bucket not in ('hour', 'day', 'week', 'month') then
    raise exception 'bucket is one of hour, day, week, month' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if observation_series.since is not null and observation_series.until is not null and observation_series.since > observation_series.until then
    raise exception 'since is before until' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if observation_series.bucket is null then
    return (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag") order by x."observed_at"), '[]'::jsonb)
      from "better_supabase"."observations" x
      join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
      where x."subject_type" = observation_series.subject_type
        and x."subject_id" = observation_series.subject_id
        and y."key" = observation_series.definition_key
        and x."status" = 'final'
        and (observation_series.since is null or x."observed_at" >= observation_series.since)
        and (observation_series.until is null or x."observed_at" < observation_series.until)
    );
  end if;
  return (
    with points as (
      select date_trunc(observation_series.bucket, x."observed_at", 'UTC') as b, x."value_number" as n, x."components" as c
      from "better_supabase"."observations" x
      join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
      where x."subject_type" = observation_series.subject_type
        and x."subject_id" = observation_series.subject_id
        and y."key" = observation_series.definition_key
        and x."status" = 'final'
        and (observation_series.since is null or x."observed_at" >= observation_series.since)
        and (observation_series.until is null or x."observed_at" < observation_series.until)
    ),
    parts as (
      select p.b, e.key, min(e.value::numeric) as lo, max(e.value::numeric) as hi, round(avg(e.value::numeric), 4) as mean
      from points p
      cross join lateral jsonb_each_text(coalesce(p.c, '{}'::jsonb)) e
      group by p.b, e.key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'bucket', g.b,
      'count', g.total,
      'min', g.lo,
      'max', g.hi,
      'avg', g.mean,
      'components', coalesce((
        select jsonb_object_agg(q.key, jsonb_build_object('min', q.lo, 'max', q.hi, 'avg', q.mean))
        from parts q where q.b = g.b
      ), '{}'::jsonb)
    ) order by g.b), '[]'::jsonb)
    from (
      select p.b, count(*) as total, min(p.n) as lo, max(p.n) as hi, round(avg(p.n), 4) as mean
      from points p
      group by p.b
    ) g
  );
end;
$$;
revoke execute on function "better_supabase"."observation_series"(text, text, text, timestamptz, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."observation_series"(text, text, text, timestamptz, timestamptz, text) to authenticated, service_role;

-- A record's latest final observation per definition key, keyed by it.
create or replace function "better_supabase"."latest_observations"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(r.key, r.item), '{}'::jsonb)
  from (
    select distinct on (y."key") y."key" as key, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") as item
    from "better_supabase"."observations" x
    join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
    where x."subject_type" = latest_observations.subject_type
      and x."subject_id" = latest_observations.subject_id
      and x."status" = 'final'
    order by y."key", x."observed_at" desc, x."created_at" desc
  ) r
$$;
revoke execute on function "better_supabase"."latest_observations"(text, text) from public, anon;
grant execute on function "better_supabase"."latest_observations"(text, text) to authenticated, service_role;

-- Records the observations a submission's fields map to. p_quiet skips a
-- submission the caller can't record for, which the trigger relies on.
create or replace function "better_supabase"."observation_submission_apply"(p_submission uuid, p_quiet boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub "better_supabase"."form_submissions"%rowtype;
  v_form jsonb;
  v_field jsonb;
  v_key text;
  v_part text;
  v_answer jsonb;
  v_values jsonb := '{}'::jsonb;
  v_entry record;
  v_definition uuid;
  v_row "better_supabase"."observations"%rowtype;
  v_def "better_supabase"."observation_definitions"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  select * into v_sub from "better_supabase"."form_submissions" x where x."id" = p_submission;
  if not found then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'form submission not found' using errcode = 'P0002', hint = 'OBSERVATION_NOT_FOUND';
  end if;
  if v_sub."subject_type" is null or v_sub."subject_id" is null then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'the submission isn''t about a record' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_sub."status"::text not in ('submitted', 'accepted') then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'the submission isn''t submitted' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sub."tenant_id", 'observations.record'), false)) and (case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then coalesce((case v_sub."subject_type"::text
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (v_sub."subject_id"::text)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (v_sub."subject_id"::text)::uuid)
      else null::text
    end) = v_sub."tenant_id"::text, false) else (case v_sub."subject_type"::text
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_sub."subject_id"::text)::uuid and s."tenant_id"::text = v_sub."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_sub."subject_id"::text)::uuid and s."organization_id"::text = v_sub."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_sub."subject_type"::text, v_sub."subject_id"::text, 'read')) end)) then
    if p_quiet then
      return '[]'::jsonb;
    end if;
    raise exception 'not allowed to record observations for this record' using errcode = '42501', hint = 'OBSERVATION_FORBIDDEN';
  end if;
  select x."definition" into v_form from "better_supabase"."form_versions" x where x."id" = v_sub."version_id";
  for v_field in
    select f from jsonb_array_elements(coalesce(v_form -> 'steps', '[]'::jsonb)) st
    cross join lateral jsonb_array_elements(coalesce(st -> 'fields', '[]'::jsonb)) f
    where jsonb_typeof(f -> 'meta' -> 'observation') = 'string'
  loop
    v_key := v_field -> 'meta' ->> 'observation';
    v_answer := v_sub."answers" -> (v_field ->> 'key');
    if v_answer is null or v_answer in ('null'::jsonb, '""'::jsonb) then
      continue;
    end if;
    v_part := v_field -> 'meta' ->> 'component';
    if v_part is null then
      v_values := v_values || jsonb_build_object(v_key, v_answer);
    else
      v_values := v_values || jsonb_build_object(v_key, coalesce(v_values -> v_key, '{}'::jsonb) || jsonb_build_object(v_part, v_answer));
    end if;
  end loop;
  for v_entry in select e.key, e.value from jsonb_each(v_values) e loop
    select x."id" into v_definition from "better_supabase"."observation_definitions" x
    where x."key" = v_entry.key and (x."tenant_id" = v_sub."tenant_id" or x."tenant_id" is null)
    order by x."tenant_id" nulls last
    limit 1;
    if v_definition is null then
      if p_quiet then
        continue;
      end if;
      raise exception 'a field names an observation definition that doesn''t exist' using errcode = 'P0002', hint = 'OBSERVATION_DEFINITION_NOT_FOUND';
    end if;
    if exists (select 1 from "better_supabase"."observations" x where x."submission_id" = v_sub."id" and x."definition_id" = v_definition) then
      continue;
    end if;
    select * into v_row from "better_supabase"."observation_insert"(v_sub."tenant_id", v_definition, v_sub."subject_type"::text, v_sub."subject_id"::text, v_entry.value, coalesce(v_sub."submitted_at", now()), null, 'form', null, v_sub."id", v_sub."respondent_id", null, null);
    select * into v_def from "better_supabase"."observation_definitions" x where x."id" = v_row."definition_id";
    v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'definitionId', v_row."definition_id", 'definitionKey', v_def."key", 'title', v_def."title", 'valueType', v_def."value_type", 'unit', v_def."unit", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'observedAt', v_row."observed_at", 'value', case v_def."value_type"
      when 'boolean' then to_jsonb(v_row."value_code" = 'true')
      when 'code' then to_jsonb(v_row."value_code")
      when 'text' then to_jsonb(v_row."value_text")
      when 'components' then v_row."components"
      else to_jsonb(v_row."value_number")
    end, 'flag', v_row."flag", 'status', v_row."status", 'replacesId', v_row."replaces_id", 'reason', v_row."reason", 'method', v_row."method", 'device', v_row."device", 'source', v_row."source", 'externalId', v_row."external_id", 'submissionId', v_row."submission_id", 'performerId', v_row."performer_id", 'note', v_row."note", 'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."observation_submission_apply"(uuid, boolean) from public, anon, authenticated;

-- Records the observations of a submitted submission, as the caller; a
-- second call records only what the first didn't.
create or replace function "better_supabase"."observations_from_submission"(submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return "better_supabase"."observation_submission_apply"(observations_from_submission.submission_id, false);
end;
$$;
revoke execute on function "better_supabase"."observations_from_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."observations_from_submission"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."observation_submission_trigger"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."status"::text = 'submitted' and (tg_op = 'INSERT' or old."status"::text is distinct from 'submitted') and new."subject_type" is not null then
    perform "better_supabase"."observation_submission_apply"(new."id", true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."observation_submission_trigger"() from public, anon, authenticated;
drop trigger if exists "bsb_observation_submission" on "better_supabase"."form_submissions";
create trigger "bsb_observation_submission"
after insert or update of "status" on "better_supabase"."form_submissions"
for each row execute function "better_supabase"."observation_submission_trigger"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."observation_definitions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."observation_definitions";
create policy bsb_tenant_scope_select on "better_supabase"."observation_definitions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" is null or "tenant_id" in (select better_supabase.tenant_ids_with('observations.read')) or "tenant_id" in (select better_supabase.member_organization_ids()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."observation_definitions";
create policy bsb_tenant_scope_insert on "better_supabase"."observation_definitions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."observation_definitions";
create policy bsb_tenant_scope_update on "better_supabase"."observation_definitions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."observation_definitions";
create policy bsb_tenant_scope_delete on "better_supabase"."observation_definitions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."observations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."observations";
create policy bsb_tenant_scope_select on "better_supabase"."observations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('observations.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."observations";
create policy bsb_tenant_scope_insert on "better_supabase"."observations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."observations";
create policy bsb_tenant_scope_update on "better_supabase"."observations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."observations";
create policy bsb_tenant_scope_delete on "better_supabase"."observations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.observations.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."record_observation"(uuid, text, text, text, jsonb, timestamptz, jsonb, jsonb);

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."save_observation_definition"(tenant uuid, key text, definition jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_observation_definition"($1, $2, $3) $$;
revoke execute on function "api"."save_observation_definition"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."save_observation_definition"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."archive_observation_definition"(definition_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_observation_definition"($1) $$;
revoke execute on function "api"."archive_observation_definition"(uuid) from public, anon;
grant execute on function "api"."archive_observation_definition"(uuid) to authenticated, service_role;

create or replace function "api"."record_observation"(tenant uuid, subject_type text, subject_id text, definition_key text, value jsonb, observed_at timestamptz default null, details jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_observation"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."record_observation"(uuid, text, text, text, jsonb, timestamptz, jsonb) from public, anon;
grant execute on function "api"."record_observation"(uuid, text, text, text, jsonb, timestamptz, jsonb) to authenticated, service_role;

create or replace function "api"."record_observations"(tenant uuid, items jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_observations"($1, $2) $$;
revoke execute on function "api"."record_observations"(uuid, jsonb) from public, anon;
grant execute on function "api"."record_observations"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."ingest_observations"(tenant uuid, items jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ingest_observations"($1, $2) $$;
revoke execute on function "api"."ingest_observations"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."ingest_observations"(uuid, jsonb) to service_role;

create or replace function "api"."amend_observation"(observation_id uuid, changes jsonb, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."amend_observation"($1, $2, $3) $$;
revoke execute on function "api"."amend_observation"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."amend_observation"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."mark_observation_error"(observation_id uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_observation_error"($1, $2) $$;
revoke execute on function "api"."mark_observation_error"(uuid, text) from public, anon;
grant execute on function "api"."mark_observation_error"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_observation_definitions"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_observation_definitions"($1, $2) $$;
revoke execute on function "api"."list_observation_definitions"(uuid, boolean) from public, anon;
grant execute on function "api"."list_observation_definitions"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_observations"(subject_type text, subject_id text, definition_key text default null, include_all boolean default false, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_observations"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_observations"(text, text, text, boolean, integer) from public, anon;
grant execute on function "api"."list_observations"(text, text, text, boolean, integer) to authenticated, service_role;

create or replace function "api"."observation_series"(subject_type text, subject_id text, definition_key text, since timestamptz default null, until timestamptz default null, bucket text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."observation_series"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."observation_series"(text, text, text, timestamptz, timestamptz, text) from public, anon;
grant execute on function "api"."observation_series"(text, text, text, timestamptz, timestamptz, text) to authenticated, service_role;

create or replace function "api"."latest_observations"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."latest_observations"($1, $2) $$;
revoke execute on function "api"."latest_observations"(text, text) from public, anon;
grant execute on function "api"."latest_observations"(text, text) to authenticated, service_role;

create or replace function "api"."observations_from_submission"(submission_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."observations_from_submission"($1) $$;
revoke execute on function "api"."observations_from_submission"(uuid) from public, anon;
grant execute on function "api"."observations_from_submission"(uuid) to authenticated, service_role;

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
