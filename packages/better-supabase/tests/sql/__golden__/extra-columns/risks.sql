-- ==== schema supabase/schemas/900_better_supabase_144_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:ee4ed3b1ae3ad162145cd379e560307818a79375e050163d2e9a161294a016a6
-- A risk register per organization: risks numbered RSK-0001, scored on a configurable likelihood by impact matrix before and after controls, with an assessment history snapshotted in versions, treatment, scheduled reviews, barriers linked through relations, and a heatmap.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."risk_matrices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."risk_matrices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risk_matrices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."risk_matrices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risk_matrices";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."risks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."risks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."risks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."risk_assessments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."risk_assessments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risk_assessments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."risk_assessments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risk_assessments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- A risk register per organization: risks scored on a likelihood by impact
-- matrix, assessed before and after controls, treated, reviewed and closed.

create table if not exists "better_supabase"."risk_matrices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- [{ value, label }] with values 1 to n; save_risk_matrix checks the shape.
  "likelihood_levels" jsonb not null check (jsonb_typeof("likelihood_levels") = 'array'),
  "impact_levels" jsonb not null check (jsonb_typeof("impact_levels") = 'array'),
  -- [{ key, label, min, max }] covering every score once.
  "bands" jsonb not null check (jsonb_typeof("bands") = 'array'),
  "scoring" text not null default 'product' check ("scoring" in ('product', 'sum')),
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
create unique index if not exists "risk_matrices_default_key" on "better_supabase"."risk_matrices" ("tenant_id") where "is_default";
alter table "better_supabase"."risk_matrices" enable row level security;
revoke all on "better_supabase"."risk_matrices" from public, anon, authenticated;
grant select on "better_supabase"."risk_matrices" to authenticated;
grant all on "better_supabase"."risk_matrices" to service_role;
drop policy if exists risk_matrices_read on "better_supabase"."risk_matrices";
create policy risk_matrices_read on "better_supabase"."risk_matrices"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- RSK-0001, from the numbering block when it numbers risks.
  "number" text not null check (length("number") between 1 and 100),
  "sequence" bigint not null,
  "matrix_id" uuid not null,
  "title" text not null check (length("title") between 1 and 300),
  "description" text check ("description" is null or length("description") <= 10000),
  -- One of options.categories; the functions check it.
  "category" text not null check (length("category") between 1 and 63),
  "cause" text check ("cause" is null or length("cause") <= 4000),
  "consequence" text check ("consequence" is null or length("consequence") <= 4000),
  "owner_id" uuid,
  "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  "treatment" text check ("treatment" is null or "treatment" in ('mitigate', 'accept', 'transfer', 'avoid')),
  -- An assessment or a review moves next_review_on this many months ahead (12 when null).
  "review_interval_months" integer check ("review_interval_months" is null or "review_interval_months" between 1 and 120),
  "next_review_on" date,
  "reviewed_at" timestamptz,
  -- The review date notify_due_risk_reviews last reported, so each lapse notifies once.
  "review_notified_for" date,
  "inherent_likelihood" integer check ("inherent_likelihood" is null or "inherent_likelihood" between 1 and 10),
  "inherent_impact" integer check ("inherent_impact" is null or "inherent_impact" between 1 and 10),
  "inherent_score" integer check ("inherent_score" is null or "inherent_score" between 1 and 100),
  "inherent_band" text,
  "residual_likelihood" integer check ("residual_likelihood" is null or "residual_likelihood" between 1 and 10),
  "residual_impact" integer check ("residual_impact" is null or "residual_impact" between 1 and 10),
  "residual_score" integer check ("residual_score" is null or "residual_score" between 1 and 100),
  "residual_band" text,
  "current_assessment_id" uuid,
  "closed_at" timestamptz,
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "id"),
  check ("status" <> 'closed' or "closed_at" is not null),
  foreign key ("tenant_id", "matrix_id") references "better_supabase"."risk_matrices" ("tenant_id", "id") on delete restrict
);
alter table "better_supabase"."risks" add column if not exists "app_note" text;
create index if not exists "risks_tenant_idx" on "better_supabase"."risks" ("tenant_id", "status", "residual_score" desc);
create index if not exists "risks_matrix_idx" on "better_supabase"."risks" ("tenant_id", "matrix_id");
create index if not exists "risks_owner_idx" on "better_supabase"."risks" ("tenant_id", "owner_id") where "owner_id" is not null;
create index if not exists "risks_review_idx" on "better_supabase"."risks" ("next_review_on") where "status" <> 'closed';
alter table "better_supabase"."risks" enable row level security;
revoke all on "better_supabase"."risks" from public, anon, authenticated;
grant select on "better_supabase"."risks" to authenticated;
grant all on "better_supabase"."risks" to service_role;
drop policy if exists risks_read on "better_supabase"."risks";
create policy risks_read on "better_supabase"."risks"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risk_assessments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "risk_id" uuid not null,
  "inherent_likelihood" integer check ("inherent_likelihood" is null or "inherent_likelihood" between 1 and 10) not null,
  "inherent_impact" integer check ("inherent_impact" is null or "inherent_impact" between 1 and 10) not null,
  "inherent_score" integer check ("inherent_score" is null or "inherent_score" between 1 and 100) not null,
  "inherent_band" text not null,
  "residual_likelihood" integer check ("residual_likelihood" is null or "residual_likelihood" between 1 and 10) not null,
  "residual_impact" integer check ("residual_impact" is null or "residual_impact" between 1 and 10) not null,
  "residual_score" integer check ("residual_score" is null or "residual_score" between 1 and 100) not null,
  "residual_band" text not null,
  "rationale" text check ("rationale" is null or length("rationale") <= 10000),
  "version_id" uuid references "better_supabase"."versions" ("id") on delete set null,
  "assessed_by" uuid,
  "assessed_at" timestamptz not null default now(),
  foreign key ("tenant_id", "risk_id") references "better_supabase"."risks" ("tenant_id", "id") on delete cascade
);
create index if not exists "risk_assessments_history_idx" on "better_supabase"."risk_assessments" ("tenant_id", "risk_id", "assessed_at" desc);
create index if not exists "risk_assessments_version_idx" on "better_supabase"."risk_assessments" ("version_id") where "version_id" is not null;
alter table "better_supabase"."risk_assessments" enable row level security;
revoke all on "better_supabase"."risk_assessments" from public, anon, authenticated;
grant select on "better_supabase"."risk_assessments" to authenticated;
grant all on "better_supabase"."risk_assessments" to service_role;
drop policy if exists risk_assessments_read on "better_supabase"."risk_assessments";
create policy risk_assessments_read on "better_supabase"."risk_assessments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));


-- The organization's default matrix, seeded from options.defaultMatrix when it
-- has no matrix yet. The other functions call it; it is not an entry point.
create or replace function "better_supabase"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."risk_matrices" x
  where x."tenant_id" = ensure_risk_matrix.tenant
  order by x."is_default" desc, x."created_at"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (
    ensure_risk_matrix.tenant, 'default', 'Default 5x5',
    '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb,
    '[{"value":1,"label":"Insignificant"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb,
    '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb,
    'product', true
  )
  on conflict do nothing
  returning "id" into v_id;
  if v_id is null then
    select x."id" into v_id from "better_supabase"."risk_matrices" x
    where x."tenant_id" = ensure_risk_matrix.tenant
    order by x."is_default" desc, x."created_at"
    limit 1;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ensure_risk_matrix"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."ensure_risk_matrix"(uuid) to service_role;

-- Creates a matrix or, with matrix_id, changes one. likelihood_levels and
-- impact_levels are [{ value, label }] with values 1 to n; bands are
-- [{ key, label, min, max }] covering every score once. A matrix risks use
-- keeps its level counts, and their scores and bands follow the new rules.
create or replace function "better_supabase"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risk_matrices";
  v_old "better_supabase"."risk_matrices";
  v_min integer;
  v_max integer;
  v_nl integer;
  v_ni integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_risk_matrix.tenant is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false))) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if coalesce(save_risk_matrix.key, '') !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key must be lowercase letters, digits, dashes and underscores' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if coalesce(length(trim(save_risk_matrix.name)), 0) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if coalesce(save_risk_matrix.scoring, '') not in ('product', 'sum') then
    raise exception 'scoring must be product or sum' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if jsonb_typeof(save_risk_matrix.likelihood_levels) is distinct from 'array' or jsonb_array_length(save_risk_matrix.likelihood_levels) not between 2 and 10 then
    raise exception 'likelihood_levels must be a list of 2 to 10 levels' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_risk_matrix.likelihood_levels) l
    where jsonb_typeof(l) <> 'object' or jsonb_typeof(l -> 'value') is distinct from 'number'
      or (l ->> 'value') !~ '^[0-9]{1,2}$' or coalesce(length(trim(l ->> 'label')), 0) not between 1 and 100
  ) then
    raise exception 'likelihood_levels values must be 1 to n, each once, with a label of 1 to 100 characters' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if (select array_agg((l ->> 'value')::integer order by (l ->> 'value')::integer) from jsonb_array_elements(save_risk_matrix.likelihood_levels) l)
    <> (select array_agg(g order by g) from generate_series(1, jsonb_array_length(save_risk_matrix.likelihood_levels)) g) then
    raise exception 'likelihood_levels values must be 1 to n, each once, with a label of 1 to 100 characters' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if jsonb_typeof(save_risk_matrix.impact_levels) is distinct from 'array' or jsonb_array_length(save_risk_matrix.impact_levels) not between 2 and 10 then
    raise exception 'impact_levels must be a list of 2 to 10 levels' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_risk_matrix.impact_levels) l
    where jsonb_typeof(l) <> 'object' or jsonb_typeof(l -> 'value') is distinct from 'number'
      or (l ->> 'value') !~ '^[0-9]{1,2}$' or coalesce(length(trim(l ->> 'label')), 0) not between 1 and 100
  ) then
    raise exception 'impact_levels values must be 1 to n, each once, with a label of 1 to 100 characters' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if (select array_agg((l ->> 'value')::integer order by (l ->> 'value')::integer) from jsonb_array_elements(save_risk_matrix.impact_levels) l)
    <> (select array_agg(g order by g) from generate_series(1, jsonb_array_length(save_risk_matrix.impact_levels)) g) then
    raise exception 'impact_levels values must be 1 to n, each once, with a label of 1 to 100 characters' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  v_nl := jsonb_array_length(save_risk_matrix.likelihood_levels);
  v_ni := jsonb_array_length(save_risk_matrix.impact_levels);
  v_min := case when save_risk_matrix.scoring = 'sum' then 2 else 1 end;
  v_max := case when save_risk_matrix.scoring = 'sum' then v_nl + v_ni else v_nl * v_ni end;
  if jsonb_typeof(save_risk_matrix.bands) is distinct from 'array' or jsonb_array_length(save_risk_matrix.bands) not between 1 and 10 then
    raise exception 'bands must be a list of 1 to 10 bands' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(save_risk_matrix.bands) b
    where jsonb_typeof(b) <> 'object' or coalesce(b ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,31}$'
      or coalesce(length(trim(b ->> 'label')), 0) not between 1 and 100
      or jsonb_typeof(b -> 'min') is distinct from 'number' or jsonb_typeof(b -> 'max') is distinct from 'number'
      or (b ->> 'min') !~ '^[0-9]{1,4}$' or (b ->> 'max') !~ '^[0-9]{1,4}$'
  ) then
    raise exception 'each band needs a key of lowercase letters, digits and underscores, a label, and whole-number min and max' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if (select count(distinct b ->> 'key') from jsonb_array_elements(save_risk_matrix.bands) b) <> jsonb_array_length(save_risk_matrix.bands) then
    raise exception 'band keys must be unique' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if exists (
    select 1 from (
      select (b ->> 'min')::integer as lo, (b ->> 'max')::integer as hi,
        lag((b ->> 'max')::integer) over (order by (b ->> 'min')::integer) as prev,
        row_number() over (order by (b ->> 'min')::integer) as n
      from jsonb_array_elements(save_risk_matrix.bands) b
    ) s
    where s.lo > s.hi or (s.n = 1 and s.lo <> v_min) or (s.n > 1 and s.lo <> s.prev + 1)
  ) or (select max((b ->> 'max')::integer) from jsonb_array_elements(save_risk_matrix.bands) b) <> v_max then
    raise exception 'bands must cover every score from the lowest to the highest without gaps or overlaps' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is not null then
    select * into v_old from "better_supabase"."risk_matrices" x
    where x."id" = save_risk_matrix.matrix_id and x."tenant_id" = save_risk_matrix.tenant
    for update;
    if not found then
      raise exception 'no such risk matrix in this organization' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
    if (jsonb_array_length(v_old."likelihood_levels") <> v_nl or jsonb_array_length(v_old."impact_levels") <> v_ni)
      and exists (select 1 from "better_supabase"."risks" y where y."tenant_id" = v_old."tenant_id" and y."matrix_id" = v_old."id") then
      raise exception 'risks use this matrix, so its level counts can''t change' using errcode = '55000', hint = 'RISK_MATRIX_IN_USE';
    end if;
  end if;
  if save_risk_matrix.is_default then
    update "better_supabase"."risk_matrices" x set "is_default" = false, "updated_at" = now()
    where x."tenant_id" = save_risk_matrix.tenant and x."is_default"
      and x."id" is distinct from save_risk_matrix.matrix_id;
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, save_risk_matrix.scoring,
      save_risk_matrix.is_default or not exists (select 1 from "better_supabase"."risk_matrices" y where y."tenant_id" = save_risk_matrix.tenant and y."is_default"))
    returning * into v_row;
    null;
  else
    update "better_supabase"."risk_matrices" x set
      "key" = save_risk_matrix.key,
      "name" = trim(save_risk_matrix.name),
      "likelihood_levels" = save_risk_matrix.likelihood_levels,
      "impact_levels" = save_risk_matrix.impact_levels,
      "bands" = save_risk_matrix.bands,
      "scoring" = save_risk_matrix.scoring,
      -- The default stays the default until another matrix takes over.
      "is_default" = x."is_default" or save_risk_matrix.is_default,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    update "better_supabase"."risks" x set
    "inherent_score" = case when x."inherent_likelihood" is null then null else (case when v_row."scoring" = 'sum' then x."inherent_likelihood" + x."inherent_impact" else x."inherent_likelihood" * x."inherent_impact" end) end,
    "inherent_band" = case when x."inherent_likelihood" is null then null else (select b ->> 'key' from jsonb_array_elements(v_row."bands") b where (case when v_row."scoring" = 'sum' then x."inherent_likelihood" + x."inherent_impact" else x."inherent_likelihood" * x."inherent_impact" end) between (b ->> 'min')::integer and (b ->> 'max')::integer limit 1) end,
    "residual_score" = case when x."residual_likelihood" is null then null else (case when v_row."scoring" = 'sum' then x."residual_likelihood" + x."residual_impact" else x."residual_likelihood" * x."residual_impact" end) end,
    "residual_band" = case when x."residual_likelihood" is null then null else (select b ->> 'key' from jsonb_array_elements(v_row."bands") b where (case when v_row."scoring" = 'sum' then x."residual_likelihood" + x."residual_impact" else x."residual_likelihood" * x."residual_impact" end) between (b ->> 'min')::integer and (b ->> 'max')::integer limit 1) end
  where x."tenant_id" = v_row."tenant_id" and x."matrix_id" = v_row."id";
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'another matrix of this organization has this key' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

-- The organization's matrices, the default first. Seeds the default matrix
-- the first time.
create or replace function "better_supabase"."list_risk_matrices"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_risk_matrices.tenant is not null and coalesce(better_supabase.can('tenant', list_risk_matrices.tenant, 'risks.read'), false))) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  perform "better_supabase"."ensure_risk_matrix"(list_risk_matrices.tenant);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."is_default" desc, x."name")
    from "better_supabase"."risk_matrices" x where x."tenant_id" = list_risk_matrices.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "better_supabase"."list_risk_matrices"(uuid) to authenticated, service_role;

-- A risk the caller writes: input is { title, description, category, cause,
-- consequence, ownerId, matrixId, reviewIntervalMonths, fields }. It starts
-- identified, on the organization's default matrix without matrixId.
create or replace function "better_supabase"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
  v_title text := trim(create_risk.input ->> 'title');
  v_category text := create_risk.input ->> 'category';
  v_matrix uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_risk.tenant is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false))) then
    raise exception 'not allowed to write risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if jsonb_typeof(create_risk.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a risk needs a title of 1 to 300 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_category is null or not (v_category = any (array['quality', 'safety', 'environment', 'security', 'compliance', 'operational', 'financial', 'strategic']::text[])) then
    raise exception 'the category is not one of options.categories' using errcode = '22023', hint = 'RISK_CATEGORY_UNKNOWN';
  end if;
  if length(create_risk.input ->> 'description') > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if length(create_risk.input ->> 'cause') > 4000 then
    raise exception 'cause is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if length(create_risk.input ->> 'consequence') > 4000 then
    raise exception 'consequence is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if create_risk.input ? 'reviewIntervalMonths' and create_risk.input ->> 'reviewIntervalMonths' is not null
    and ((create_risk.input ->> 'reviewIntervalMonths') !~ '^[0-9]{1,3}$' or (create_risk.input ->> 'reviewIntervalMonths')::integer not between 1 and 120) then
    raise exception 'reviewIntervalMonths is a whole number from 1 to 120' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if create_risk.input ? 'fields' and jsonb_typeof(create_risk.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  v_matrix := coalesce(nullif(create_risk.input ->> 'matrixId', '')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  if not exists (
    select 1 from "better_supabase"."risk_matrices" x where x."id" = v_matrix and x."tenant_id" = create_risk.tenant
  ) then
    raise exception 'no such risk matrix in this organization' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_risk_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_risk.tenant, create_risk.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'risk' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'risk' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_risk.tenant::text || ':risk', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."risks" x where x."tenant_id" = create_risk.tenant;
  v_number := 'RSK-' || v_seq::text;
  end if;
  insert into "better_supabase"."risks" ("tenant_id", "number", "sequence", "matrix_id", "title", "category", "description", "cause", "consequence", "owner_id", "review_interval_months", "created_by")
  values (create_risk.tenant, v_number, v_seq, v_matrix, v_title, v_category, nullif(trim(create_risk.input ->> 'description'), ''), nullif(trim(create_risk.input ->> 'cause'), ''), nullif(trim(create_risk.input ->> 'consequence'), ''), nullif(create_risk.input ->> 'ownerId', '')::uuid, (create_risk.input ->> 'reviewIntervalMonths')::integer, auth.uid())
  returning * into v_row;
  update "better_supabase"."risks" x set "app_note" = case when coalesce(create_risk.input -> 'fields', '{}'::jsonb) ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."risks", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(coalesce(create_risk.input -> 'fields', '{}'::jsonb)) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_risk_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_risk"(uuid, jsonb) to authenticated, service_role;

-- Changes a risk's title, description, category, cause, consequence, owner,
-- review interval, extra fields, or its matrix before the first assessment.
create or replace function "better_supabase"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
  v_title text;
  v_category text;
  v_matrix uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false))) then
    raise exception 'not allowed to write risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the risk is closed' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if jsonb_typeof(update_risk.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  v_title := case when update_risk.changes ? 'title' then trim(update_risk.changes ->> 'title') else v_row."title" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a risk needs a title of 1 to 300 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  v_category := case when update_risk.changes ? 'category' then update_risk.changes ->> 'category' else v_row."category" end;
  if v_category is null or not (v_category = any (array['quality', 'safety', 'environment', 'security', 'compliance', 'operational', 'financial', 'strategic']::text[])) then
    raise exception 'the category is not one of options.categories' using errcode = '22023', hint = 'RISK_CATEGORY_UNKNOWN';
  end if;
  if length(update_risk.changes ->> 'description') > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if length(update_risk.changes ->> 'cause') > 4000 then
    raise exception 'cause is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if length(update_risk.changes ->> 'consequence') > 4000 then
    raise exception 'consequence is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if update_risk.changes ? 'reviewIntervalMonths' and update_risk.changes ->> 'reviewIntervalMonths' is not null
    and ((update_risk.changes ->> 'reviewIntervalMonths') !~ '^[0-9]{1,3}$' or (update_risk.changes ->> 'reviewIntervalMonths')::integer not between 1 and 120) then
    raise exception 'reviewIntervalMonths is a whole number from 1 to 120' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if update_risk.changes ? 'fields' and jsonb_typeof(update_risk.changes -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  v_matrix := v_row."matrix_id";
  if update_risk.changes ? 'matrixId' and (update_risk.changes ->> 'matrixId')::uuid is distinct from v_row."matrix_id" then
    if v_row."current_assessment_id" is not null then
      raise exception 'a risk''s matrix changes only before its first assessment' using errcode = '22023', hint = 'RISK_INVALID';
    end if;
    v_matrix := (update_risk.changes ->> 'matrixId')::uuid;
    if not exists (
    select 1 from "better_supabase"."risk_matrices" x where x."id" = v_matrix and x."tenant_id" = v_row."tenant_id"
  ) then
    raise exception 'no such risk matrix in this organization' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
  end if;
  end if;
  update "better_supabase"."risks" x set
    "title" = v_title,
    "category" = v_category,
    "description" = case when update_risk.changes ? 'description' then nullif(trim(update_risk.changes ->> 'description'), '') else x."description" end,
    "cause" = case when update_risk.changes ? 'cause' then nullif(trim(update_risk.changes ->> 'cause'), '') else x."cause" end,
    "consequence" = case when update_risk.changes ? 'consequence' then nullif(trim(update_risk.changes ->> 'consequence'), '') else x."consequence" end,
    "owner_id" = case when update_risk.changes ? 'ownerId' then nullif(update_risk.changes ->> 'ownerId', '')::uuid else x."owner_id" end,
    "review_interval_months" = case when update_risk.changes ? 'reviewIntervalMonths' then (update_risk.changes ->> 'reviewIntervalMonths')::integer else x."review_interval_months" end,
    "matrix_id" = v_matrix,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."risks" x set "app_note" = case when coalesce(update_risk.changes -> 'fields', '{}'::jsonb) ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."risks", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(coalesce(update_risk.changes -> 'fields', '{}'::jsonb)) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_risk"(uuid, jsonb) to authenticated, service_role;


-- Scores a risk before (inherent) and after (residual) its controls on its
-- matrix, records the assessment with a frozen version of the risk, and moves
-- its next review ahead. An identified risk becomes assessed.
create or replace function "better_supabase"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
  v_matrix "better_supabase"."risk_matrices";
  v_assessment uuid := gen_random_uuid();
  v_inherent integer;
  v_residual integer;
  v_inherent_band text;
  v_residual_band text;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false))) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the risk is closed' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if length(assess_risk.rationale) > 10000 then
    raise exception 'a rationale is at most 10000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  if assess_risk.inherent_likelihood is null or assess_risk.inherent_impact is null
    or assess_risk.inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels")
    or assess_risk.inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels")
    or assess_risk.residual_likelihood is null or assess_risk.residual_impact is null
    or assess_risk.residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels")
    or assess_risk.residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a likelihood or impact is not a level of the risk''s matrix' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := (case when v_matrix."scoring" = 'sum' then assess_risk.inherent_likelihood + assess_risk.inherent_impact else assess_risk.inherent_likelihood * assess_risk.inherent_impact end);
  v_residual := (case when v_matrix."scoring" = 'sum' then assess_risk.residual_likelihood + assess_risk.residual_impact else assess_risk.residual_likelihood * assess_risk.residual_impact end);
  v_inherent_band := (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where v_inherent between (b ->> 'min')::integer and (b ->> 'max')::integer limit 1);
  v_residual_band := (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where v_residual between (b ->> 'min')::integer and (b ->> 'max')::integer limit 1);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_risk_assess"(uuid, integer, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::integer, $3::integer)', v_hook::oid::regproc)
        using v_row."id", v_inherent, v_residual;
    end if;
  end;
  v_version := "better_supabase"."version_insert"(v_row."tenant_id", 'risk', v_row."id"::text,
    jsonb_build_object('title', v_row."title", 'category', v_row."category", 'description', v_row."description", 'cause', v_row."cause", 'consequence', v_row."consequence", 'matrixId', v_row."matrix_id", 'assessmentId', v_assessment,
      'inherent', jsonb_build_object('likelihood', assess_risk.inherent_likelihood, 'impact', assess_risk.inherent_impact, 'score', v_inherent, 'band', v_inherent_band),
      'residual', jsonb_build_object('likelihood', assess_risk.residual_likelihood, 'impact', assess_risk.residual_impact, 'score', v_residual, 'band', v_residual_band),
      'rationale', assess_risk.rationale),
    null, 'assessment', 'manual', true, auth.uid());
  insert into "better_supabase"."risk_assessments" ("id", "tenant_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale", "version_id", "assessed_by")
  values (v_assessment, v_row."tenant_id", v_row."id", assess_risk.inherent_likelihood, assess_risk.inherent_impact, v_inherent, v_inherent_band, assess_risk.residual_likelihood, assess_risk.residual_impact, v_residual, v_residual_band, nullif(trim(assess_risk.rationale), ''), (v_version ->> 'id')::uuid, auth.uid());
  update "better_supabase"."risks" x set
    "inherent_likelihood" = assess_risk.inherent_likelihood,
    "inherent_impact" = assess_risk.inherent_impact,
    "inherent_score" = v_inherent,
    "inherent_band" = v_inherent_band,
    "residual_likelihood" = assess_risk.residual_likelihood,
    "residual_impact" = assess_risk.residual_impact,
    "residual_score" = v_residual,
    "residual_band" = v_residual_band,
    "current_assessment_id" = v_assessment,
    "status" = case when x."status" = 'identified' then 'assessed' else x."status" end,
    "next_review_on" = (current_date + make_interval(months => coalesce(x."review_interval_months", 12)))::date,
    "review_notified_for" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_risk_assess"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

-- Sets how a risk is treated: mitigate and transfer make it treating, accept
-- makes it accepted (risks.manage) and avoid closes it.
create or replace function "better_supabase"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false))) then
    raise exception 'not allowed to write risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the risk is closed' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if coalesce(set_risk_treatment.treatment, '') not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'treatment is mitigate, accept, transfer or avoid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false))) then
    raise exception 'accepting a risk needs the manage permission' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if length(set_risk_treatment.note) > 4000 then
    raise exception 'a note is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  update "better_supabase"."risks" x set
    "treatment" = set_risk_treatment.treatment,
    "status" = case set_risk_treatment.treatment when 'accept' then 'accepted' when 'avoid' then 'closed' else 'treating' end,
    "closed_at" = case when set_risk_treatment.treatment = 'avoid' then now() else x."closed_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

-- Records that a risk was reviewed and moves its next review ahead by its
-- review interval (12 months when unset).
create or replace function "better_supabase"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false))) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the risk is closed' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if length(review_risk.note) > 4000 then
    raise exception 'a note is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  update "better_supabase"."risks" x set
    "reviewed_at" = now(),
    "next_review_on" = (current_date + make_interval(months => coalesce(x."review_interval_months", 12)))::date,
    "review_notified_for" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."review_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_risk"(uuid, text) to authenticated, service_role;

-- Closes a risk with a reason. A closed risk takes no more changes.
create or replace function "better_supabase"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false))) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'the risk is closed' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if coalesce(length(trim(close_risk.reason)), 0) not between 1 and 4000 then
    raise exception 'closing a risk needs a reason of 1 to 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_risk_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."risks" x set
    "status" = 'closed',
    "closed_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_risk_close"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."close_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_risk"(uuid, text) to authenticated, service_role;

-- A risk with its matrix, its assessments (newest first), its barriers (the
-- mitigated_by links) and the cases it materialized as.
create or replace function "better_supabase"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
  v_matrix "better_supabase"."risk_matrices";
begin
  select * into v_row from "better_supabase"."risks" x where x."id" = get_risk.risk_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false))) then
    raise exception 'no such risk' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note")) || jsonb_build_object(
    'matrix', jsonb_build_object('id', v_matrix."id", 'organizationId', v_matrix."tenant_id", 'key', v_matrix."key", 'name', v_matrix."name", 'likelihoodLevels', v_matrix."likelihood_levels", 'impactLevels', v_matrix."impact_levels", 'bands', v_matrix."bands", 'scoring', v_matrix."scoring", 'isDefault', v_matrix."is_default", 'createdAt', v_matrix."created_at", 'updatedAt', v_matrix."updated_at"),
    'assessments', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'riskId', y."risk_id", 'inherent', jsonb_build_object('likelihood', y."inherent_likelihood", 'impact', y."inherent_impact", 'score', y."inherent_score", 'band', y."inherent_band"), 'residual', jsonb_build_object('likelihood', y."residual_likelihood", 'impact', y."residual_impact", 'score', y."residual_score", 'band', y."residual_band"), 'rationale', y."rationale", 'versionId', y."version_id", 'assessedBy', y."assessed_by", 'assessedAt', y."assessed_at") order by y."assessed_at" desc)
      from "better_supabase"."risk_assessments" y where y."tenant_id" = v_row."tenant_id" and y."risk_id" = v_row."id"
    ), '[]'::jsonb),
    'barriers', '[]'::jsonb,
    'cases', '[]'::jsonb
  );
end;
$$;
revoke execute on function "better_supabase"."get_risk"(uuid) from public, anon;
grant execute on function "better_supabase"."get_risk"(uuid) to authenticated, service_role;

-- The organization's risks, the highest residual score first. filters is
-- { category, band (residual), ownerId, status, reviewDue, search, limit,
-- offset }; closed risks are left out unless status asks for them.
create or replace function "better_supabase"."list_risks"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_risks.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_risks.tenant is not null and coalesce(better_supabase.can('tenant', list_risks.tenant, 'risks.read'), false))) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) order by x."residual_score" desc nulls last, x."sequence")
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when v_filters ? 'status' then x."status" = v_filters ->> 'status' else x."status" <> 'closed' end)
        and (not v_filters ? 'category' or x."category" = v_filters ->> 'category')
        and (not v_filters ? 'band' or x."residual_band" = v_filters ->> 'band')
        and (not v_filters ? 'ownerId' or x."owner_id" = (v_filters ->> 'ownerId')::uuid)
        and (coalesce((v_filters ->> 'reviewDue')::boolean, false) is false or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
      order by x."residual_score" desc nulls last, x."sequence"
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_risks"(uuid, jsonb) to authenticated, service_role;

-- A matrix (the default without matrix_id) with one cell per likelihood and
-- impact: the open risks scored there, on their residual or inherent score.
create or replace function "better_supabase"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_matrix "better_supabase"."risk_matrices";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (risk_heatmap.tenant is not null and coalesce(better_supabase.can('tenant', risk_heatmap.tenant, 'risks.read'), false))) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if coalesce(risk_heatmap.basis, '') not in ('residual', 'inherent') then
    raise exception 'basis is residual or inherent' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x
  where x."tenant_id" = risk_heatmap.tenant
    and x."id" = coalesce(risk_heatmap.matrix_id, "better_supabase"."ensure_risk_matrix"(risk_heatmap.tenant));
  if not found then
    raise exception 'no such risk matrix in this organization' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'matrix', jsonb_build_object('id', v_matrix."id", 'organizationId', v_matrix."tenant_id", 'key', v_matrix."key", 'name', v_matrix."name", 'likelihoodLevels', v_matrix."likelihood_levels", 'impactLevels', v_matrix."impact_levels", 'bands', v_matrix."bands", 'scoring', v_matrix."scoring", 'isDefault', v_matrix."is_default", 'createdAt', v_matrix."created_at", 'updatedAt', v_matrix."updated_at"),
    'basis', risk_heatmap.basis,
    'cells', coalesce((
      select jsonb_agg(jsonb_build_object(
        'likelihood', c.likelihood, 'impact', c.impact,
        'score', (case when v_matrix."scoring" = 'sum' then c.likelihood + c.impact else c.likelihood * c.impact end),
        'band', (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (case when v_matrix."scoring" = 'sum' then c.likelihood + c.impact else c.likelihood * c.impact end) between (b ->> 'min')::integer and (b ->> 'max')::integer limit 1),
        'count', coalesce(cardinality(c.ids), 0), 'riskIds', to_jsonb(coalesce(c.ids, '{}'::uuid[]))
      ) order by c.likelihood, c.impact)
      from (
        select l.l as likelihood, i.i as impact, (
          select array_agg(x."id" order by x."sequence")
          from "better_supabase"."risks" x
          where x."tenant_id" = v_matrix."tenant_id" and x."matrix_id" = v_matrix."id"
            and x."status" <> 'closed' and x."archived_at" is null
            and case when risk_heatmap.basis = 'inherent'
              then x."inherent_likelihood" = l.l and x."inherent_impact" = i.i
              else x."residual_likelihood" = l.l and x."residual_impact" = i.i end
        ) as ids
        from generate_series(1, jsonb_array_length(v_matrix."likelihood_levels")) l (l)
        cross join generate_series(1, jsonb_array_length(v_matrix."impact_levels")) i (i)
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

-- Reports each open risk whose review date has come once per date: a
-- risk.review_date_reached event and, with notifications, a notification to its owner.
-- Run it daily from a job (the risks.reviews block timer).
create or replace function "better_supabase"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_claims text;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."risks" x
    where x."status" <> 'closed' and x."archived_at" is null
      and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on"
    for update skip locked
  loop
    null;
    
    update "better_supabase"."risks" x set "review_notified_for" = v_row."next_review_on" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_risk_reviews"() from public, anon, authenticated;
grant execute on function "better_supabase"."notify_due_risk_reviews"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."risk_matrices";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_select on "better_supabase"."risk_matrices" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_insert on "better_supabase"."risk_matrices" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_update on "better_supabase"."risk_matrices" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_delete on "better_supabase"."risk_matrices" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."risks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."risks";
create policy bsb_tenant_scope_select on "better_supabase"."risks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risks";
create policy bsb_tenant_scope_insert on "better_supabase"."risks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."risks";
create policy bsb_tenant_scope_update on "better_supabase"."risks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risks";
create policy bsb_tenant_scope_delete on "better_supabase"."risks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."risk_assessments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_select on "better_supabase"."risk_assessments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_insert on "better_supabase"."risk_assessments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_update on "better_supabase"."risk_assessments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_delete on "better_supabase"."risk_assessments" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_144_risks.sql
-- better-supabase module: risks
-- @bsb-block-data risks
-- @bsb-hash sha256:c9230989b9b165e7c6a5c6270cc003d39bc7d1c14630c7d79e62a15caf694035
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('risks', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
