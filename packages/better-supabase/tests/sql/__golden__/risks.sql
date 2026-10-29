-- ==== alone: schema supabase/schemas/900_better_supabase_145_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:91fa44bfb089045b61ef8327f8ee7d28ef05c420a791bc3fc6b7424d7b998f5d
-- Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.
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
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.

create table if not exists "better_supabase"."risk_matrices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "likelihood_levels" jsonb not null,
  "impact_levels" jsonb not null,
  "bands" jsonb not null,
  "scoring" text not null default 'product' check ("scoring" in ('product', 'sum')),
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
create unique index if not exists risk_matrices_default_idx on "better_supabase"."risk_matrices" ("tenant_id") where "is_default";
alter table "better_supabase"."risk_matrices" enable row level security;
revoke all on "better_supabase"."risk_matrices" from public, anon, authenticated;
grant select on "better_supabase"."risk_matrices" to authenticated;
grant all on "better_supabase"."risk_matrices" to service_role;
create policy risk_matrices_read on better_supabase.risk_matrices
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "matrix_id" uuid not null,
  "number" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "category" text,
  "cause" text,
  "consequence" text,
  "owner_id" uuid,
  "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  "treatment" text check ("treatment" in ('mitigate', 'accept', 'transfer', 'avoid')),
  "review_interval_months" integer check ("review_interval_months" between 1 and 120),
  "next_review_on" date,
  "inherent_likelihood" integer,
  "inherent_impact" integer,
  "inherent_score" integer,
  "inherent_band" text,
  "residual_likelihood" integer,
  "residual_impact" integer,
  "residual_score" integer,
  "residual_band" text,
  "current_assessment_id" uuid,
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("tenant_id", "matrix_id") references "better_supabase"."risk_matrices" ("tenant_id", "id")
);
create index if not exists risks_status_idx on "better_supabase"."risks" ("tenant_id", "status");
create index if not exists risks_review_idx on "better_supabase"."risks" ("tenant_id", "next_review_on");
alter table "better_supabase"."risks" enable row level security;
revoke all on "better_supabase"."risks" from public, anon, authenticated;
grant select on "better_supabase"."risks" to authenticated;
grant all on "better_supabase"."risks" to service_role;
create policy risks_read on better_supabase.risks
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risk_assessments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "risk_id" uuid not null,
  "inherent_likelihood" integer not null,
  "inherent_impact" integer not null,
  "inherent_score" integer not null,
  "inherent_band" text not null,
  "residual_likelihood" integer not null,
  "residual_impact" integer not null,
  "residual_score" integer not null,
  "residual_band" text not null,
  "rationale" text,
  "assessed_by" uuid default auth.uid(),
  "assessed_at" timestamptz not null default now(),
  foreign key ("risk_id") references "better_supabase"."risks" ("id") on delete cascade
);
create index if not exists risk_assessments_parent_idx on "better_supabase"."risk_assessments" ("risk_id");
alter table "better_supabase"."risk_assessments" enable row level security;
revoke all on "better_supabase"."risk_assessments" from public, anon, authenticated;
grant select on "better_supabase"."risk_assessments" to authenticated;
grant all on "better_supabase"."risk_assessments" to service_role;
create policy risk_assessments_read on better_supabase.risk_assessments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create or replace function "better_supabase"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" into v_id from "better_supabase"."risk_matrices" x where x."tenant_id" = ensure_risk_matrix.tenant and x."is_default" limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning "id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "better_supabase"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risk_matrices"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    raise exception 'the matrix shape is invalid' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "likelihood_levels" = excluded."likelihood_levels", "impact_levels" = excluded."impact_levels", "bands" = excluded."bands", "scoring" = excluded."scoring", "is_default" = excluded."is_default", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."risk_matrices" x set "key" = save_risk_matrix.key, "name" = trim(save_risk_matrix.name), "likelihood_levels" = save_risk_matrix.likelihood_levels, "impact_levels" = save_risk_matrix.impact_levels, "bands" = save_risk_matrix.bands, "scoring" = coalesce(save_risk_matrix.scoring, 'product'), "is_default" = coalesce(save_risk_matrix.is_default, false), "updated_at" = now()
      where x."id" = save_risk_matrix.matrix_id and x."tenant_id" = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      raise exception 'risk matrix not found' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default");
end;
$$;
revoke execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default") order by x."is_default" desc, x."key"), '[]'::jsonb)
  from "better_supabase"."risk_matrices" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
$$;
revoke execute on function "better_supabase"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "better_supabase"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false) then
    raise exception 'not allowed to create risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  insert into "better_supabase"."risks" ("tenant_id", "matrix_id", "number", "title", "description", "category", "cause", "consequence", "owner_id", "review_interval_months")
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from "better_supabase"."risks" x where x."tenant_id" = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row."category" := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row."cause" := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row."consequence" := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row."review_interval_months" := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update "better_supabase"."risks" x set "title" = v_row."title", "description" = v_row."description", "category" = v_row."category", "cause" = v_row."cause", "consequence" = v_row."consequence", "owner_id" = v_row."owner_id", "review_interval_months" = v_row."review_interval_months", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_matrix "better_supabase"."risk_matrices"%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment "better_supabase"."risk_assessments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") or residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a level is out of range' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := case when v_matrix."scoring" = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix."scoring" = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into "better_supabase"."risk_assessments" ("tenant_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale")
  values (v_row."tenant_id", v_row."id", inherent_likelihood, inherent_impact, v_inherent, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_inherent and (b ->> 'max')::integer >= v_inherent limit 1), residual_likelihood, residual_impact, v_residual, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_residual and (b ->> 'max')::integer >= v_residual limit 1), assess_risk.rationale)
  returning * into v_assessment;
  update "better_supabase"."risks" x set "inherent_likelihood" = inherent_likelihood, "inherent_impact" = inherent_impact, "inherent_score" = v_inherent, "inherent_band" = v_assessment."inherent_band", "residual_likelihood" = residual_likelihood, "residual_impact" = residual_impact, "residual_score" = v_residual, "residual_band" = v_assessment."residual_band", "current_assessment_id" = v_assessment."id", "status" = case when "status" = 'identified' then 'assessed' else "status" end, "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "better_supabase"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'the treatment is invalid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'accepting a risk needs risks.manage' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "treatment" = set_risk_treatment.treatment, "status" = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from "better_supabase"."risks" x where x."id" = get_risk.risk_id;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'rationale', x."rationale", 'assessedAt', x."assessed_at") order by x."assessed_at" desc), '[]'::jsonb) into v_assessments from "better_supabase"."risk_assessments" x where x."risk_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('assessments', v_assessments);
end;
$$;
revoke execute on function "better_supabase"."get_risk"(uuid) from public, anon;
grant execute on function "better_supabase"."get_risk"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'matrixId', x."matrix_id", 'number', x."number", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'inherentLikelihood', x."inherent_likelihood", 'inherentImpact', x."inherent_impact", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualLikelihood', x."residual_likelihood", 'residualImpact', x."residual_impact", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'currentAssessmentId', x."current_assessment_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."risks" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    and (not (filters ? 'category') or x."category" = filters ->> 'category')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x."next_review_on" is not null and x."next_review_on" <= current_date))
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
$$;
revoke execute on function "better_supabase"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', jsonb_build_object('id', m."id", 'organizationId', m."tenant_id", 'key', m."key", 'name', m."name", 'likelihoodLevels', m."likelihood_levels", 'impactLevels', m."impact_levels", 'bands', m."bands", 'scoring', m."scoring", 'isDefault', m."is_default"),
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x."inherent_likelihood" else x."residual_likelihood" end as l,
      case when $3 = 'inherent' then x."inherent_impact" else x."residual_impact" end as i,
      count(*) as c,
      jsonb_agg(x."id") as ids
    from "better_supabase"."risks" x
    where x."tenant_id" = $1 and x."status" <> 'closed' and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    group by 1, 2
  ) s
  cross join (select * from "better_supabase"."risk_matrices" where "id" = coalesce($2, (select "id" from "better_supabase"."risk_matrices" where "tenant_id" = $1 and "is_default" limit 1))) m
  group by m."id", m."tenant_id", m."key", m."name", m."likelihood_levels", m."impact_levels", m."bands", m."scoring", m."is_default"
$$;
revoke execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "better_supabase"."risks" x where x."status" <> 'closed' and x."next_review_on" is not null and x."next_review_on" <= current_date
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_risk_reviews"() from public, anon;
grant execute on function "better_supabase"."notify_due_risk_reviews"() to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_145_risks.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_145_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:b28157a08470b87d94bf296df48d3cd8e89a97f7e32687b3b2dee86b51db3f51
-- Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.
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
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.

create table if not exists "better_supabase"."risk_matrices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "likelihood_levels" jsonb not null,
  "impact_levels" jsonb not null,
  "bands" jsonb not null,
  "scoring" text not null default 'product' check ("scoring" in ('product', 'sum')),
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
create unique index if not exists risk_matrices_default_idx on "better_supabase"."risk_matrices" ("tenant_id") where "is_default";
alter table "better_supabase"."risk_matrices" enable row level security;
revoke all on "better_supabase"."risk_matrices" from public, anon, authenticated;
grant select on "better_supabase"."risk_matrices" to authenticated;
grant all on "better_supabase"."risk_matrices" to service_role;
create policy risk_matrices_read on better_supabase.risk_matrices
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "matrix_id" uuid not null,
  "number" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "category" text,
  "cause" text,
  "consequence" text,
  "owner_id" uuid,
  "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  "treatment" text check ("treatment" in ('mitigate', 'accept', 'transfer', 'avoid')),
  "review_interval_months" integer check ("review_interval_months" between 1 and 120),
  "next_review_on" date,
  "inherent_likelihood" integer,
  "inherent_impact" integer,
  "inherent_score" integer,
  "inherent_band" text,
  "residual_likelihood" integer,
  "residual_impact" integer,
  "residual_score" integer,
  "residual_band" text,
  "current_assessment_id" uuid,
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("tenant_id", "matrix_id") references "better_supabase"."risk_matrices" ("tenant_id", "id")
);
create index if not exists risks_status_idx on "better_supabase"."risks" ("tenant_id", "status");
create index if not exists risks_review_idx on "better_supabase"."risks" ("tenant_id", "next_review_on");
alter table "better_supabase"."risks" enable row level security;
revoke all on "better_supabase"."risks" from public, anon, authenticated;
grant select on "better_supabase"."risks" to authenticated;
grant all on "better_supabase"."risks" to service_role;
create policy risks_read on better_supabase.risks
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risk_assessments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "risk_id" uuid not null,
  "inherent_likelihood" integer not null,
  "inherent_impact" integer not null,
  "inherent_score" integer not null,
  "inherent_band" text not null,
  "residual_likelihood" integer not null,
  "residual_impact" integer not null,
  "residual_score" integer not null,
  "residual_band" text not null,
  "rationale" text,
  "assessed_by" uuid default auth.uid(),
  "assessed_at" timestamptz not null default now(),
  foreign key ("risk_id") references "better_supabase"."risks" ("id") on delete cascade
);
create index if not exists risk_assessments_parent_idx on "better_supabase"."risk_assessments" ("risk_id");
alter table "better_supabase"."risk_assessments" enable row level security;
revoke all on "better_supabase"."risk_assessments" from public, anon, authenticated;
grant select on "better_supabase"."risk_assessments" to authenticated;
grant all on "better_supabase"."risk_assessments" to service_role;
create policy risk_assessments_read on better_supabase.risk_assessments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create or replace function "better_supabase"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" into v_id from "better_supabase"."risk_matrices" x where x."tenant_id" = ensure_risk_matrix.tenant and x."is_default" limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning "id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "better_supabase"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risk_matrices"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    raise exception 'the matrix shape is invalid' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "likelihood_levels" = excluded."likelihood_levels", "impact_levels" = excluded."impact_levels", "bands" = excluded."bands", "scoring" = excluded."scoring", "is_default" = excluded."is_default", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."risk_matrices" x set "key" = save_risk_matrix.key, "name" = trim(save_risk_matrix.name), "likelihood_levels" = save_risk_matrix.likelihood_levels, "impact_levels" = save_risk_matrix.impact_levels, "bands" = save_risk_matrix.bands, "scoring" = coalesce(save_risk_matrix.scoring, 'product'), "is_default" = coalesce(save_risk_matrix.is_default, false), "updated_at" = now()
      where x."id" = save_risk_matrix.matrix_id and x."tenant_id" = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      raise exception 'risk matrix not found' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
  end if;
  if v_created then
    perform "better_supabase".emit_event('risk_matrix.created', jsonb_build_object('organizationId', v_row."tenant_id", 'matrixId', v_row."id", 'key', v_row."key"), 'risk-matrices/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk_matrix.created',
    category => 'data',
    target_type => 'risk_matrix',
    record_id => v_row."id"::text,
    summary => 'saved risk matrix',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'matrixId', v_row."id", 'key', v_row."key")
  );
  else
    perform "better_supabase".emit_event('risk_matrix.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'matrixId', v_row."id", 'key', v_row."key"), 'risk-matrices/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk_matrix.updated',
    category => 'data',
    target_type => 'risk_matrix',
    record_id => v_row."id"::text,
    summary => 'saved risk matrix',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'matrixId', v_row."id", 'key', v_row."key")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default");
end;
$$;
revoke execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default") order by x."is_default" desc, x."key"), '[]'::jsonb)
  from "better_supabase"."risk_matrices" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
$$;
revoke execute on function "better_supabase"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "better_supabase"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false) then
    raise exception 'not allowed to create risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  insert into "better_supabase"."risks" ("tenant_id", "matrix_id", "number", "title", "description", "category", "cause", "consequence", "owner_id", "review_interval_months")
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from "better_supabase"."risks" x where x."tenant_id" = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  perform "better_supabase".emit_event('risk.created', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.created',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'created risk ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row."category" := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row."cause" := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row."consequence" := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row."review_interval_months" := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update "better_supabase"."risks" x set "title" = v_row."title", "description" = v_row."description", "category" = v_row."category", "cause" = v_row."cause", "consequence" = v_row."consequence", "owner_id" = v_row."owner_id", "review_interval_months" = v_row."review_interval_months", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('risk.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'changed', to_jsonb(v_changed)), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.updated',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'changed risk ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'changed', to_jsonb(v_changed))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_matrix "better_supabase"."risk_matrices"%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment "better_supabase"."risk_assessments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") or residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a level is out of range' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := case when v_matrix."scoring" = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix."scoring" = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into "better_supabase"."risk_assessments" ("tenant_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale")
  values (v_row."tenant_id", v_row."id", inherent_likelihood, inherent_impact, v_inherent, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_inherent and (b ->> 'max')::integer >= v_inherent limit 1), residual_likelihood, residual_impact, v_residual, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_residual and (b ->> 'max')::integer >= v_residual limit 1), assess_risk.rationale)
  returning * into v_assessment;
  update "better_supabase"."risks" x set "inherent_likelihood" = inherent_likelihood, "inherent_impact" = inherent_impact, "inherent_score" = v_inherent, "inherent_band" = v_assessment."inherent_band", "residual_likelihood" = residual_likelihood, "residual_impact" = residual_impact, "residual_score" = v_residual, "residual_band" = v_assessment."residual_band", "current_assessment_id" = v_assessment."id", "status" = case when "status" = 'identified' then 'assessed' else "status" end, "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('risk.assessed', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'inherentBand', v_row."inherent_band", 'residualBand', v_row."residual_band"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.assessed',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'assessed risk ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'inherentBand', v_row."inherent_band", 'residualBand', v_row."residual_band")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "better_supabase"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'the treatment is invalid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'accepting a risk needs risks.manage' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "treatment" = set_risk_treatment.treatment, "status" = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('risk.treatment_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'treatment', v_row."treatment"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.treatment_changed',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'changed treatment of ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'treatment', v_row."treatment")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('risk.reviewed', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.reviewed',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'reviewed risk ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('risk.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.closed',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'closed risk ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from "better_supabase"."risks" x where x."id" = get_risk.risk_id;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'rationale', x."rationale", 'assessedAt', x."assessed_at") order by x."assessed_at" desc), '[]'::jsonb) into v_assessments from "better_supabase"."risk_assessments" x where x."risk_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('assessments', v_assessments);
end;
$$;
revoke execute on function "better_supabase"."get_risk"(uuid) from public, anon;
grant execute on function "better_supabase"."get_risk"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'matrixId', x."matrix_id", 'number', x."number", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'inherentLikelihood', x."inherent_likelihood", 'inherentImpact', x."inherent_impact", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualLikelihood', x."residual_likelihood", 'residualImpact', x."residual_impact", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'currentAssessmentId', x."current_assessment_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."risks" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    and (not (filters ? 'category') or x."category" = filters ->> 'category')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x."next_review_on" is not null and x."next_review_on" <= current_date))
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
$$;
revoke execute on function "better_supabase"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', jsonb_build_object('id', m."id", 'organizationId', m."tenant_id", 'key', m."key", 'name', m."name", 'likelihoodLevels', m."likelihood_levels", 'impactLevels', m."impact_levels", 'bands', m."bands", 'scoring', m."scoring", 'isDefault', m."is_default"),
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x."inherent_likelihood" else x."residual_likelihood" end as l,
      case when $3 = 'inherent' then x."inherent_impact" else x."residual_impact" end as i,
      count(*) as c,
      jsonb_agg(x."id") as ids
    from "better_supabase"."risks" x
    where x."tenant_id" = $1 and x."status" <> 'closed' and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    group by 1, 2
  ) s
  cross join (select * from "better_supabase"."risk_matrices" where "id" = coalesce($2, (select "id" from "better_supabase"."risk_matrices" where "tenant_id" = $1 and "is_default" limit 1))) m
  group by m."id", m."tenant_id", m."key", m."name", m."likelihood_levels", m."impact_levels", m."bands", m."scoring", m."is_default"
$$;
revoke execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "better_supabase"."risks" x where x."status" <> 'closed' and x."next_review_on" is not null and x."next_review_on" <= current_date
  loop
    perform "better_supabase".emit_event('risk.review_reminded', jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'nextReviewOn', v_row."next_review_on"::text), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.review_reminded',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    summary => 'risk review due ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'riskId', v_row."id", 'number', v_row."number", 'nextReviewOn', v_row."next_review_on"::text)
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_risk_reviews"() from public, anon;
grant execute on function "better_supabase"."notify_due_risk_reviews"() to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_145_risks.sql
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

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_145_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:ce14219362c13b27f45b6c61f5f1fdf60f3fafdff0d83d0d5cfbd6bd7c14b3b1
-- Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.
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
    drop policy if exists bsb_tenant_scope on "app_private"."risk_matrices";
    drop policy if exists bsb_tenant_scope_select on "app_private"."risk_matrices";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."risk_matrices";
    drop policy if exists bsb_tenant_scope_update on "app_private"."risk_matrices";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."risk_matrices";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."risks";
    drop policy if exists bsb_tenant_scope_select on "app_private"."risks";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."risks";
    drop policy if exists bsb_tenant_scope_update on "app_private"."risks";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."risks";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."risk_assessments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."risk_assessments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."risk_assessments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."risk_assessments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."risk_assessments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.

create table if not exists "app_private"."risk_matrices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "likelihood_levels" jsonb not null,
  "impact_levels" jsonb not null,
  "bands" jsonb not null,
  "scoring" text not null default 'product' check ("scoring" in ('product', 'sum')),
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
create unique index if not exists risk_matrices_default_idx on "app_private"."risk_matrices" ("tenant_id") where "is_default";
alter table "app_private"."risk_matrices" enable row level security;
revoke all on "app_private"."risk_matrices" from public, anon, authenticated;
grant select on "app_private"."risk_matrices" to authenticated;
grant all on "app_private"."risk_matrices" to service_role;
create policy risk_matrices_read on app_private.risk_matrices
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "app_private"."risks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "matrix_id" uuid not null,
  "number" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "category" text,
  "cause" text,
  "consequence" text,
  "owner_id" uuid,
  "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  "treatment" text check ("treatment" in ('mitigate', 'accept', 'transfer', 'avoid')),
  "review_interval_months" integer check ("review_interval_months" between 1 and 120),
  "next_review_on" date,
  "inherent_likelihood" integer,
  "inherent_impact" integer,
  "inherent_score" integer,
  "inherent_band" text,
  "residual_likelihood" integer,
  "residual_impact" integer,
  "residual_score" integer,
  "residual_band" text,
  "current_assessment_id" uuid,
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("tenant_id", "matrix_id") references "app_private"."risk_matrices" ("tenant_id", "id")
);
create index if not exists risks_status_idx on "app_private"."risks" ("tenant_id", "status");
create index if not exists risks_review_idx on "app_private"."risks" ("tenant_id", "next_review_on");
alter table "app_private"."risks" enable row level security;
revoke all on "app_private"."risks" from public, anon, authenticated;
grant select on "app_private"."risks" to authenticated;
grant all on "app_private"."risks" to service_role;
create policy risks_read on app_private.risks
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "app_private"."risk_assessments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "risk_id" uuid not null,
  "inherent_likelihood" integer not null,
  "inherent_impact" integer not null,
  "inherent_score" integer not null,
  "inherent_band" text not null,
  "residual_likelihood" integer not null,
  "residual_impact" integer not null,
  "residual_score" integer not null,
  "residual_band" text not null,
  "rationale" text,
  "assessed_by" uuid default auth.uid(),
  "assessed_at" timestamptz not null default now(),
  foreign key ("risk_id") references "app_private"."risks" ("id") on delete cascade
);
create index if not exists risk_assessments_parent_idx on "app_private"."risk_assessments" ("risk_id");
alter table "app_private"."risk_assessments" enable row level security;
revoke all on "app_private"."risk_assessments" from public, anon, authenticated;
grant select on "app_private"."risk_assessments" to authenticated;
grant all on "app_private"."risk_assessments" to service_role;
create policy risk_assessments_read on app_private.risk_assessments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create or replace function "app_private"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" into v_id from "app_private"."risk_matrices" x where x."tenant_id" = ensure_risk_matrix.tenant and x."is_default" limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "app_private"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning "id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "app_private"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "app_private"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "app_private"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risk_matrices"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    raise exception 'the matrix shape is invalid' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into "app_private"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "likelihood_levels" = excluded."likelihood_levels", "impact_levels" = excluded."impact_levels", "bands" = excluded."bands", "scoring" = excluded."scoring", "is_default" = excluded."is_default", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "app_private"."risk_matrices" x set "key" = save_risk_matrix.key, "name" = trim(save_risk_matrix.name), "likelihood_levels" = save_risk_matrix.likelihood_levels, "impact_levels" = save_risk_matrix.impact_levels, "bands" = save_risk_matrix.bands, "scoring" = coalesce(save_risk_matrix.scoring, 'product'), "is_default" = coalesce(save_risk_matrix.is_default, false), "updated_at" = now()
      where x."id" = save_risk_matrix.matrix_id and x."tenant_id" = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      raise exception 'risk matrix not found' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default");
end;
$$;
revoke execute on function "app_private"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "app_private"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "app_private"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default") order by x."is_default" desc, x."key"), '[]'::jsonb)
  from "app_private"."risk_matrices" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
$$;
revoke execute on function "app_private"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "app_private"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "app_private"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row "app_private"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false) then
    raise exception 'not allowed to create risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, "app_private"."ensure_risk_matrix"(create_risk.tenant));
  insert into "app_private"."risks" ("tenant_id", "matrix_id", "number", "title", "description", "category", "cause", "consequence", "owner_id", "review_interval_months")
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from "app_private"."risks" x where x."tenant_id" = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risks"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row."category" := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row."cause" := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row."consequence" := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row."review_interval_months" := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update "app_private"."risks" x set "title" = v_row."title", "description" = v_row."description", "category" = v_row."category", "cause" = v_row."cause", "consequence" = v_row."consequence", "owner_id" = v_row."owner_id", "review_interval_months" = v_row."review_interval_months", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risks"%rowtype;
  v_matrix "app_private"."risk_matrices"%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment "app_private"."risk_assessments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  select * into v_matrix from "app_private"."risk_matrices" x where x."id" = v_row."matrix_id";
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") or residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a level is out of range' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := case when v_matrix."scoring" = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix."scoring" = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into "app_private"."risk_assessments" ("tenant_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale")
  values (v_row."tenant_id", v_row."id", inherent_likelihood, inherent_impact, v_inherent, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_inherent and (b ->> 'max')::integer >= v_inherent limit 1), residual_likelihood, residual_impact, v_residual, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_residual and (b ->> 'max')::integer >= v_residual limit 1), assess_risk.rationale)
  returning * into v_assessment;
  update "app_private"."risks" x set "inherent_likelihood" = inherent_likelihood, "inherent_impact" = inherent_impact, "inherent_score" = v_inherent, "inherent_band" = v_assessment."inherent_band", "residual_likelihood" = residual_likelihood, "residual_impact" = residual_impact, "residual_score" = v_residual, "residual_band" = v_assessment."residual_band", "current_assessment_id" = v_assessment."id", "status" = case when "status" = 'identified' then 'assessed' else "status" end, "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "app_private"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "app_private"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'the treatment is invalid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'accepting a risk needs risks.manage' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "app_private"."risks" x set "treatment" = set_risk_treatment.treatment, "status" = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "app_private"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "app_private"."risks" x set "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."review_risk"(uuid, text) from public, anon;
grant execute on function "app_private"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "app_private"."risks" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."close_risk"(uuid, text) from public, anon;
grant execute on function "app_private"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."risks"%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from "app_private"."risks" x where x."id" = get_risk.risk_id;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'rationale', x."rationale", 'assessedAt', x."assessed_at") order by x."assessed_at" desc), '[]'::jsonb) into v_assessments from "app_private"."risk_assessments" x where x."risk_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('assessments', v_assessments);
end;
$$;
revoke execute on function "app_private"."get_risk"(uuid) from public, anon;
grant execute on function "app_private"."get_risk"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'matrixId', x."matrix_id", 'number', x."number", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'inherentLikelihood', x."inherent_likelihood", 'inherentImpact', x."inherent_impact", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualLikelihood', x."residual_likelihood", 'residualImpact', x."residual_impact", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'currentAssessmentId', x."current_assessment_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb)
  from "app_private"."risks" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    and (not (filters ? 'category') or x."category" = filters ->> 'category')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x."next_review_on" is not null and x."next_review_on" <= current_date))
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
$$;
revoke execute on function "app_private"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', jsonb_build_object('id', m."id", 'organizationId', m."tenant_id", 'key', m."key", 'name', m."name", 'likelihoodLevels', m."likelihood_levels", 'impactLevels', m."impact_levels", 'bands', m."bands", 'scoring', m."scoring", 'isDefault', m."is_default"),
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x."inherent_likelihood" else x."residual_likelihood" end as l,
      case when $3 = 'inherent' then x."inherent_impact" else x."residual_impact" end as i,
      count(*) as c,
      jsonb_agg(x."id") as ids
    from "app_private"."risks" x
    where x."tenant_id" = $1 and x."status" <> 'closed' and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    group by 1, 2
  ) s
  cross join (select * from "app_private"."risk_matrices" where "id" = coalesce($2, (select "id" from "app_private"."risk_matrices" where "tenant_id" = $1 and "is_default" limit 1))) m
  group by m."id", m."tenant_id", m."key", m."name", m."likelihood_levels", m."impact_levels", m."bands", m."scoring", m."is_default"
$$;
revoke execute on function "app_private"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "app_private"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "app_private"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "app_private"."risks" x where x."status" <> 'closed' and x."next_review_on" is not null and x."next_review_on" <= current_date
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."notify_due_risk_reviews"() from public, anon;
grant execute on function "app_private"."notify_due_risk_reviews"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."risk_matrices";
drop policy if exists bsb_tenant_scope_select on "app_private"."risk_matrices";
create policy bsb_tenant_scope_select on "app_private"."risk_matrices" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."risk_matrices";
create policy bsb_tenant_scope_insert on "app_private"."risk_matrices" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."risk_matrices";
create policy bsb_tenant_scope_update on "app_private"."risk_matrices" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."risk_matrices";
create policy bsb_tenant_scope_delete on "app_private"."risk_matrices" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."risks";
drop policy if exists bsb_tenant_scope_select on "app_private"."risks";
create policy bsb_tenant_scope_select on "app_private"."risks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."risks";
create policy bsb_tenant_scope_insert on "app_private"."risks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."risks";
create policy bsb_tenant_scope_update on "app_private"."risks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."risks";
create policy bsb_tenant_scope_delete on "app_private"."risks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."risk_assessments";
drop policy if exists bsb_tenant_scope_select on "app_private"."risk_assessments";
create policy bsb_tenant_scope_select on "app_private"."risk_assessments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."risk_assessments";
create policy bsb_tenant_scope_insert on "app_private"."risk_assessments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."risk_assessments";
create policy bsb_tenant_scope_update on "app_private"."risk_assessments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."risk_assessments";
create policy bsb_tenant_scope_delete on "app_private"."risk_assessments" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_145_risks.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_145_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:1d4662e54b0e2d323aabb26ea542356678ec75c19aca3af65b6c3451353317da
-- Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.
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
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.

create table if not exists "better_supabase"."risk_matrices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "likelihood_levels" jsonb not null,
  "impact_levels" jsonb not null,
  "bands" jsonb not null,
  "scoring" text not null default 'product' check ("scoring" in ('product', 'sum')),
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
create unique index if not exists risk_matrices_default_idx on "better_supabase"."risk_matrices" ("tenant_id") where "is_default";
alter table "better_supabase"."risk_matrices" enable row level security;
revoke all on "better_supabase"."risk_matrices" from public, anon, authenticated;
grant select on "better_supabase"."risk_matrices" to authenticated;
grant all on "better_supabase"."risk_matrices" to service_role;
create policy risk_matrices_read on better_supabase.risk_matrices
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "matrix_id" uuid not null,
  "number" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "category" text,
  "cause" text,
  "consequence" text,
  "owner_id" uuid,
  "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  "treatment" text check ("treatment" in ('mitigate', 'accept', 'transfer', 'avoid')),
  "review_interval_months" integer check ("review_interval_months" between 1 and 120),
  "next_review_on" date,
  "inherent_likelihood" integer,
  "inherent_impact" integer,
  "inherent_score" integer,
  "inherent_band" text,
  "residual_likelihood" integer,
  "residual_impact" integer,
  "residual_score" integer,
  "residual_band" text,
  "current_assessment_id" uuid,
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("tenant_id", "matrix_id") references "better_supabase"."risk_matrices" ("tenant_id", "id")
);
create index if not exists risks_status_idx on "better_supabase"."risks" ("tenant_id", "status");
create index if not exists risks_review_idx on "better_supabase"."risks" ("tenant_id", "next_review_on");
alter table "better_supabase"."risks" enable row level security;
revoke all on "better_supabase"."risks" from public, anon, authenticated;
grant select on "better_supabase"."risks" to authenticated;
grant all on "better_supabase"."risks" to service_role;
create policy risks_read on better_supabase.risks
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risk_assessments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "risk_id" uuid not null,
  "inherent_likelihood" integer not null,
  "inherent_impact" integer not null,
  "inherent_score" integer not null,
  "inherent_band" text not null,
  "residual_likelihood" integer not null,
  "residual_impact" integer not null,
  "residual_score" integer not null,
  "residual_band" text not null,
  "rationale" text,
  "assessed_by" uuid default auth.uid(),
  "assessed_at" timestamptz not null default now(),
  foreign key ("risk_id") references "better_supabase"."risks" ("id") on delete cascade
);
create index if not exists risk_assessments_parent_idx on "better_supabase"."risk_assessments" ("risk_id");
alter table "better_supabase"."risk_assessments" enable row level security;
revoke all on "better_supabase"."risk_assessments" from public, anon, authenticated;
grant select on "better_supabase"."risk_assessments" to authenticated;
grant all on "better_supabase"."risk_assessments" to service_role;
create policy risk_assessments_read on better_supabase.risk_assessments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create or replace function "better_supabase"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" into v_id from "better_supabase"."risk_matrices" x where x."tenant_id" = ensure_risk_matrix.tenant and x."is_default" limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning "id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "better_supabase"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risk_matrices"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    raise exception 'the matrix shape is invalid' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "likelihood_levels" = excluded."likelihood_levels", "impact_levels" = excluded."impact_levels", "bands" = excluded."bands", "scoring" = excluded."scoring", "is_default" = excluded."is_default", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."risk_matrices" x set "key" = save_risk_matrix.key, "name" = trim(save_risk_matrix.name), "likelihood_levels" = save_risk_matrix.likelihood_levels, "impact_levels" = save_risk_matrix.impact_levels, "bands" = save_risk_matrix.bands, "scoring" = coalesce(save_risk_matrix.scoring, 'product'), "is_default" = coalesce(save_risk_matrix.is_default, false), "updated_at" = now()
      where x."id" = save_risk_matrix.matrix_id and x."tenant_id" = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      raise exception 'risk matrix not found' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default");
end;
$$;
revoke execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default") order by x."is_default" desc, x."key"), '[]'::jsonb)
  from "better_supabase"."risk_matrices" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
$$;
revoke execute on function "better_supabase"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "better_supabase"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false) then
    raise exception 'not allowed to create risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  insert into "better_supabase"."risks" ("tenant_id", "matrix_id", "number", "title", "description", "category", "cause", "consequence", "owner_id", "review_interval_months")
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from "better_supabase"."risks" x where x."tenant_id" = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row."category" := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row."cause" := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row."consequence" := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row."review_interval_months" := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update "better_supabase"."risks" x set "title" = v_row."title", "description" = v_row."description", "category" = v_row."category", "cause" = v_row."cause", "consequence" = v_row."consequence", "owner_id" = v_row."owner_id", "review_interval_months" = v_row."review_interval_months", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_matrix "better_supabase"."risk_matrices"%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment "better_supabase"."risk_assessments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") or residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a level is out of range' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := case when v_matrix."scoring" = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix."scoring" = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into "better_supabase"."risk_assessments" ("tenant_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale")
  values (v_row."tenant_id", v_row."id", inherent_likelihood, inherent_impact, v_inherent, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_inherent and (b ->> 'max')::integer >= v_inherent limit 1), residual_likelihood, residual_impact, v_residual, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_residual and (b ->> 'max')::integer >= v_residual limit 1), assess_risk.rationale)
  returning * into v_assessment;
  update "better_supabase"."risks" x set "inherent_likelihood" = inherent_likelihood, "inherent_impact" = inherent_impact, "inherent_score" = v_inherent, "inherent_band" = v_assessment."inherent_band", "residual_likelihood" = residual_likelihood, "residual_impact" = residual_impact, "residual_score" = v_residual, "residual_band" = v_assessment."residual_band", "current_assessment_id" = v_assessment."id", "status" = case when "status" = 'identified' then 'assessed' else "status" end, "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "better_supabase"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'the treatment is invalid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'accepting a risk needs risks.manage' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "treatment" = set_risk_treatment.treatment, "status" = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from "better_supabase"."risks" x where x."id" = get_risk.risk_id;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'rationale', x."rationale", 'assessedAt', x."assessed_at") order by x."assessed_at" desc), '[]'::jsonb) into v_assessments from "better_supabase"."risk_assessments" x where x."risk_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('assessments', v_assessments);
end;
$$;
revoke execute on function "better_supabase"."get_risk"(uuid) from public, anon;
grant execute on function "better_supabase"."get_risk"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'matrixId', x."matrix_id", 'number', x."number", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'inherentLikelihood', x."inherent_likelihood", 'inherentImpact', x."inherent_impact", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualLikelihood', x."residual_likelihood", 'residualImpact', x."residual_impact", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'currentAssessmentId', x."current_assessment_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."risks" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    and (not (filters ? 'category') or x."category" = filters ->> 'category')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x."next_review_on" is not null and x."next_review_on" <= current_date))
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
$$;
revoke execute on function "better_supabase"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', jsonb_build_object('id', m."id", 'organizationId', m."tenant_id", 'key', m."key", 'name', m."name", 'likelihoodLevels', m."likelihood_levels", 'impactLevels', m."impact_levels", 'bands', m."bands", 'scoring', m."scoring", 'isDefault', m."is_default"),
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x."inherent_likelihood" else x."residual_likelihood" end as l,
      case when $3 = 'inherent' then x."inherent_impact" else x."residual_impact" end as i,
      count(*) as c,
      jsonb_agg(x."id") as ids
    from "better_supabase"."risks" x
    where x."tenant_id" = $1 and x."status" <> 'closed' and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    group by 1, 2
  ) s
  cross join (select * from "better_supabase"."risk_matrices" where "id" = coalesce($2, (select "id" from "better_supabase"."risk_matrices" where "tenant_id" = $1 and "is_default" limit 1))) m
  group by m."id", m."tenant_id", m."key", m."name", m."likelihood_levels", m."impact_levels", m."bands", m."scoring", m."is_default"
$$;
revoke execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "better_supabase"."risks" x where x."status" <> 'closed' and x."next_review_on" is not null and x."next_review_on" <= current_date
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_risk_reviews"() from public, anon;
grant execute on function "better_supabase"."notify_due_risk_reviews"() to authenticated, service_role;

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

-- blocks.risks.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."ensure_risk_matrix"(tenant uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ensure_risk_matrix"($1) $$;
revoke execute on function "api"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "api"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "api"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_risk_matrix"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "api"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "api"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_risk_matrices"($1) $$;
revoke execute on function "api"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "api"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "api"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_risk"($1, $2) $$;
revoke execute on function "api"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_risk"($1, $2) $$;
revoke execute on function "api"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assess_risk"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "api"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "api"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_risk_treatment"($1, $2, $3) $$;
revoke execute on function "api"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "api"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."review_risk"($1, $2) $$;
revoke execute on function "api"."review_risk"(uuid, text) from public, anon;
grant execute on function "api"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "api"."close_risk"(risk_id uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_risk"($1, $2) $$;
revoke execute on function "api"."close_risk"(uuid, text) from public, anon;
grant execute on function "api"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "api"."get_risk"(risk_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_risk"($1) $$;
revoke execute on function "api"."get_risk"(uuid) from public, anon;
grant execute on function "api"."get_risk"(uuid) to authenticated, service_role;

create or replace function "api"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_risks"($1, $2) $$;
revoke execute on function "api"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."risk_heatmap"($1, $2, $3) $$;
revoke execute on function "api"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "api"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."notify_due_risk_reviews"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_due_risk_reviews"() $$;
revoke execute on function "api"."notify_due_risk_reviews"() from public, anon;
grant execute on function "api"."notify_due_risk_reviews"() to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_145_risks.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_145_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:ffa6aaa84f857ff6ba8fcac6c2f1cbaf4298dfe723c5c83f9fa62683c920d7ad
-- Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.
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
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.

-- better_supabase.risk_matrices is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."risk_matrices" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."risk_matrices" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."risk_matrices" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_]{0,40}$');
alter table "better_supabase"."risk_matrices" add column if not exists "name" text;
alter table "better_supabase"."risk_matrices" add column if not exists "likelihood_levels" jsonb;
alter table "better_supabase"."risk_matrices" add column if not exists "impact_levels" jsonb;
alter table "better_supabase"."risk_matrices" add column if not exists "bands" jsonb;
alter table "better_supabase"."risk_matrices" add column if not exists "scoring" text not null default 'product' check ("scoring" in ('product', 'sum'));
alter table "better_supabase"."risk_matrices" add column if not exists "is_default" boolean not null default false;
alter table "better_supabase"."risk_matrices" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."risk_matrices" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists risk_matrices_default_idx on "better_supabase"."risk_matrices" ("tenant_id") where "is_default";
alter table "better_supabase"."risk_matrices" enable row level security;
grant select on "better_supabase"."risk_matrices" to authenticated;
grant all on "better_supabase"."risk_matrices" to service_role;
create policy bsb_risk_matrices_select on better_supabase.risk_matrices
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

-- better_supabase.risks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."risks" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."risks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."risks" add column if not exists "matrix_id" uuid;
alter table "better_supabase"."risks" add column if not exists "number" text;
alter table "better_supabase"."risks" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."risks" add column if not exists "description" text;
alter table "better_supabase"."risks" add column if not exists "category" text;
alter table "better_supabase"."risks" add column if not exists "cause" text;
alter table "better_supabase"."risks" add column if not exists "consequence" text;
alter table "better_supabase"."risks" add column if not exists "owner_id" uuid;
alter table "better_supabase"."risks" add column if not exists "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed'));
alter table "better_supabase"."risks" add column if not exists "treatment" text check ("treatment" in ('mitigate', 'accept', 'transfer', 'avoid'));
alter table "better_supabase"."risks" add column if not exists "review_interval_months" integer check ("review_interval_months" between 1 and 120);
alter table "better_supabase"."risks" add column if not exists "next_review_on" date;
alter table "better_supabase"."risks" add column if not exists "inherent_likelihood" integer;
alter table "better_supabase"."risks" add column if not exists "inherent_impact" integer;
alter table "better_supabase"."risks" add column if not exists "inherent_score" integer;
alter table "better_supabase"."risks" add column if not exists "inherent_band" text;
alter table "better_supabase"."risks" add column if not exists "residual_likelihood" integer;
alter table "better_supabase"."risks" add column if not exists "residual_impact" integer;
alter table "better_supabase"."risks" add column if not exists "residual_score" integer;
alter table "better_supabase"."risks" add column if not exists "residual_band" text;
alter table "better_supabase"."risks" add column if not exists "current_assessment_id" uuid;
alter table "better_supabase"."risks" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."risks" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."risks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."risks" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists risks_status_idx on "better_supabase"."risks" ("tenant_id", "status");
create index if not exists risks_review_idx on "better_supabase"."risks" ("tenant_id", "next_review_on");
alter table "better_supabase"."risks" enable row level security;
grant select on "better_supabase"."risks" to authenticated;
grant all on "better_supabase"."risks" to service_role;
create policy bsb_risks_select on better_supabase.risks
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

-- better_supabase.risk_assessments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."risk_assessments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."risk_assessments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."risk_assessments" add column if not exists "risk_id" uuid;
alter table "better_supabase"."risk_assessments" add column if not exists "inherent_likelihood" integer;
alter table "better_supabase"."risk_assessments" add column if not exists "inherent_impact" integer;
alter table "better_supabase"."risk_assessments" add column if not exists "inherent_score" integer;
alter table "better_supabase"."risk_assessments" add column if not exists "inherent_band" text;
alter table "better_supabase"."risk_assessments" add column if not exists "residual_likelihood" integer;
alter table "better_supabase"."risk_assessments" add column if not exists "residual_impact" integer;
alter table "better_supabase"."risk_assessments" add column if not exists "residual_score" integer;
alter table "better_supabase"."risk_assessments" add column if not exists "residual_band" text;
alter table "better_supabase"."risk_assessments" add column if not exists "rationale" text;
alter table "better_supabase"."risk_assessments" add column if not exists "assessed_by" uuid default auth.uid();
alter table "better_supabase"."risk_assessments" add column if not exists "assessed_at" timestamptz not null default now();
create index if not exists risk_assessments_parent_idx on "better_supabase"."risk_assessments" ("risk_id");
alter table "better_supabase"."risk_assessments" enable row level security;
grant select on "better_supabase"."risk_assessments" to authenticated;
grant all on "better_supabase"."risk_assessments" to service_role;
create policy bsb_risk_assessments_select on better_supabase.risk_assessments
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('risks.read')));

create or replace function "better_supabase"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" into v_id from "better_supabase"."risk_matrices" x where x."tenant_id" = ensure_risk_matrix.tenant and x."is_default" limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning "id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "better_supabase"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risk_matrices"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    raise exception 'the matrix shape is invalid' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into "better_supabase"."risk_matrices" ("tenant_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "likelihood_levels" = excluded."likelihood_levels", "impact_levels" = excluded."impact_levels", "bands" = excluded."bands", "scoring" = excluded."scoring", "is_default" = excluded."is_default", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."risk_matrices" x set "key" = save_risk_matrix.key, "name" = trim(save_risk_matrix.name), "likelihood_levels" = save_risk_matrix.likelihood_levels, "impact_levels" = save_risk_matrix.impact_levels, "bands" = save_risk_matrix.bands, "scoring" = coalesce(save_risk_matrix.scoring, 'product'), "is_default" = coalesce(save_risk_matrix.is_default, false), "updated_at" = now()
      where x."id" = save_risk_matrix.matrix_id and x."tenant_id" = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      raise exception 'risk matrix not found' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default");
end;
$$;
revoke execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default") order by x."is_default" desc, x."key"), '[]'::jsonb)
  from "better_supabase"."risk_matrices" x
  where x."tenant_id" = $1 and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
$$;
revoke execute on function "better_supabase"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "better_supabase"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false) then
    raise exception 'not allowed to create risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  insert into "better_supabase"."risks" ("tenant_id", "matrix_id", "number", "title", "description", "category", "cause", "consequence", "owner_id", "review_interval_months")
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from "better_supabase"."risks" x where x."tenant_id" = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row."category" := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row."cause" := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row."consequence" := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row."review_interval_months" := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update "better_supabase"."risks" x set "title" = v_row."title", "description" = v_row."description", "category" = v_row."category", "cause" = v_row."cause", "consequence" = v_row."consequence", "owner_id" = v_row."owner_id", "review_interval_months" = v_row."review_interval_months", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_matrix "better_supabase"."risk_matrices"%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment "better_supabase"."risk_assessments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.assess'), false) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") or residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a level is out of range' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := case when v_matrix."scoring" = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix."scoring" = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into "better_supabase"."risk_assessments" ("tenant_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale")
  values (v_row."tenant_id", v_row."id", inherent_likelihood, inherent_impact, v_inherent, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_inherent and (b ->> 'max')::integer >= v_inherent limit 1), residual_likelihood, residual_impact, v_residual, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_residual and (b ->> 'max')::integer >= v_residual limit 1), assess_risk.rationale)
  returning * into v_assessment;
  update "better_supabase"."risks" x set "inherent_likelihood" = inherent_likelihood, "inherent_impact" = inherent_impact, "inherent_score" = v_inherent, "inherent_band" = v_assessment."inherent_band", "residual_likelihood" = residual_likelihood, "residual_impact" = residual_impact, "residual_score" = v_residual, "residual_band" = v_assessment."residual_band", "current_assessment_id" = v_assessment."id", "status" = case when "status" = 'identified' then 'assessed' else "status" end, "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "better_supabase"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'the treatment is invalid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'accepting a risk needs risks.manage' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "treatment" = set_risk_treatment.treatment, "status" = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.write'), false) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.manage'), false) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from "better_supabase"."risks" x where x."id" = get_risk.risk_id;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'rationale', x."rationale", 'assessedAt', x."assessed_at") order by x."assessed_at" desc), '[]'::jsonb) into v_assessments from "better_supabase"."risk_assessments" x where x."risk_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('assessments', v_assessments);
end;
$$;
revoke execute on function "better_supabase"."get_risk"(uuid) from public, anon;
grant execute on function "better_supabase"."get_risk"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'matrixId', x."matrix_id", 'number', x."number", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'inherentLikelihood', x."inherent_likelihood", 'inherentImpact', x."inherent_impact", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualLikelihood', x."residual_likelihood", 'residualImpact', x."residual_impact", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'currentAssessmentId', x."current_assessment_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."risks" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    and (not (filters ? 'category') or x."category" = filters ->> 'category')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x."next_review_on" is not null and x."next_review_on" <= current_date))
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
$$;
revoke execute on function "better_supabase"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', jsonb_build_object('id', m."id", 'organizationId', m."tenant_id", 'key', m."key", 'name', m."name", 'likelihoodLevels', m."likelihood_levels", 'impactLevels', m."impact_levels", 'bands', m."bands", 'scoring', m."scoring", 'isDefault', m."is_default"),
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x."inherent_likelihood" else x."residual_likelihood" end as l,
      case when $3 = 'inherent' then x."inherent_impact" else x."residual_impact" end as i,
      count(*) as c,
      jsonb_agg(x."id") as ids
    from "better_supabase"."risks" x
    where x."tenant_id" = $1 and x."status" <> 'closed' and x."tenant_id" in (select better_supabase.tenant_ids_with('risks.read'))
    group by 1, 2
  ) s
  cross join (select * from "better_supabase"."risk_matrices" where "id" = coalesce($2, (select "id" from "better_supabase"."risk_matrices" where "tenant_id" = $1 and "is_default" limit 1))) m
  group by m."id", m."tenant_id", m."key", m."name", m."likelihood_levels", m."impact_levels", m."bands", m."scoring", m."is_default"
$$;
revoke execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "better_supabase"."risks" x where x."status" <> 'closed' and x."next_review_on" is not null and x."next_review_on" <= current_date
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_risk_reviews"() from public, anon;
grant execute on function "better_supabase"."notify_due_risk_reviews"() to authenticated, service_role;

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_145_risks.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_145_risks.sql
-- better-supabase module: risks
-- @bsb-block risks@1 managed
-- @bsb-hash sha256:07b2b457debda988a8619c8694026bb7f292725778dec7095ff4fa064dd25c3e
-- Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.
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
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.

create table if not exists "better_supabase"."risk_matrices" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "likelihood_levels" jsonb not null,
  "impact_levels" jsonb not null,
  "bands" jsonb not null,
  "scoring" text not null default 'product' check ("scoring" in ('product', 'sum')),
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key")
);
create unique index if not exists risk_matrices_default_idx on "better_supabase"."risk_matrices" ("org_id") where "is_default";
alter table "better_supabase"."risk_matrices" enable row level security;
revoke all on "better_supabase"."risk_matrices" from public, anon, authenticated;
grant select on "better_supabase"."risk_matrices" to authenticated;
grant all on "better_supabase"."risk_matrices" to service_role;
create policy risk_matrices_read on better_supabase.risk_matrices
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "matrix_id" uuid not null,
  "number" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "category" text,
  "cause" text,
  "consequence" text,
  "owner_id" uuid,
  "status" text not null default 'identified' check ("status" in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  "treatment" text check ("treatment" in ('mitigate', 'accept', 'transfer', 'avoid')),
  "review_interval_months" integer check ("review_interval_months" between 1 and 120),
  "next_review_on" date,
  "inherent_likelihood" integer,
  "inherent_impact" integer,
  "inherent_score" integer,
  "inherent_band" text,
  "residual_likelihood" integer,
  "residual_impact" integer,
  "residual_score" integer,
  "residual_band" text,
  "current_assessment_id" uuid,
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "number"),
  foreign key ("org_id", "matrix_id") references "better_supabase"."risk_matrices" ("org_id", "id")
);
create index if not exists risks_status_idx on "better_supabase"."risks" ("org_id", "status");
create index if not exists risks_review_idx on "better_supabase"."risks" ("org_id", "next_review_on");
alter table "better_supabase"."risks" enable row level security;
revoke all on "better_supabase"."risks" from public, anon, authenticated;
grant select on "better_supabase"."risks" to authenticated;
grant all on "better_supabase"."risks" to service_role;
create policy risks_read on better_supabase.risks
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('risks.read')));

create table if not exists "better_supabase"."risk_assessments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "risk_id" uuid not null,
  "inherent_likelihood" integer not null,
  "inherent_impact" integer not null,
  "inherent_score" integer not null,
  "inherent_band" text not null,
  "residual_likelihood" integer not null,
  "residual_impact" integer not null,
  "residual_score" integer not null,
  "residual_band" text not null,
  "rationale" text,
  "assessed_by" uuid default auth.uid(),
  "assessed_at" timestamptz not null default now(),
  foreign key ("risk_id") references "better_supabase"."risks" ("id") on delete cascade
);
create index if not exists risk_assessments_parent_idx on "better_supabase"."risk_assessments" ("risk_id");
alter table "better_supabase"."risk_assessments" enable row level security;
revoke all on "better_supabase"."risk_assessments" from public, anon, authenticated;
grant select on "better_supabase"."risk_assessments" to authenticated;
grant all on "better_supabase"."risk_assessments" to service_role;
create policy risk_assessments_read on better_supabase.risk_assessments
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('risks.read')));

create or replace function "better_supabase"."ensure_risk_matrix"(tenant uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" into v_id from "better_supabase"."risk_matrices" x where x."org_id" = ensure_risk_matrix.tenant and x."is_default" limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into "better_supabase"."risk_matrices" ("org_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning "id" into v_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ensure_risk_matrix"(uuid) from public, anon;
grant execute on function "better_supabase"."ensure_risk_matrix"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_risk_matrix"(tenant uuid, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risk_matrices"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_risk_matrix.tenant, 'risks.manage'), false) then
    raise exception 'not allowed to manage risk matrices' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    raise exception 'the matrix shape is invalid' using errcode = '22023', hint = 'RISK_MATRIX_INVALID';
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into "better_supabase"."risk_matrices" ("org_id", "key", "name", "likelihood_levels", "impact_levels", "bands", "scoring", "is_default")
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict ("org_id", "key") do update
      set "name" = excluded."name", "likelihood_levels" = excluded."likelihood_levels", "impact_levels" = excluded."impact_levels", "bands" = excluded."bands", "scoring" = excluded."scoring", "is_default" = excluded."is_default", "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."risk_matrices" x set "key" = save_risk_matrix.key, "name" = trim(save_risk_matrix.name), "likelihood_levels" = save_risk_matrix.likelihood_levels, "impact_levels" = save_risk_matrix.impact_levels, "bands" = save_risk_matrix.bands, "scoring" = coalesce(save_risk_matrix.scoring, 'product'), "is_default" = coalesce(save_risk_matrix.is_default, false), "updated_at" = now()
      where x."id" = save_risk_matrix.matrix_id and x."org_id" = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      raise exception 'risk matrix not found' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
    end if;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'likelihoodLevels', v_row."likelihood_levels", 'impactLevels', v_row."impact_levels", 'bands', v_row."bands", 'scoring', v_row."scoring", 'isDefault', v_row."is_default");
end;
$$;
revoke execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_risk_matrix"(uuid, text, text, jsonb, jsonb, jsonb, text, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risk_matrices"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'likelihoodLevels', x."likelihood_levels", 'impactLevels', x."impact_levels", 'bands', x."bands", 'scoring', x."scoring", 'isDefault', x."is_default") order by x."is_default" desc, x."key"), '[]'::jsonb)
  from "better_supabase"."risk_matrices" x
  where x."org_id" = $1 and x."org_id" in (select better_supabase.tenant_ids_with('risks.read'))
$$;
revoke execute on function "better_supabase"."list_risk_matrices"(uuid) from public, anon;
grant execute on function "better_supabase"."list_risk_matrices"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."create_risk"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false) then
    raise exception 'not allowed to create risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  insert into "better_supabase"."risks" ("org_id", "matrix_id", "number", "title", "description", "category", "cause", "consequence", "owner_id", "review_interval_months")
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from "better_supabase"."risks" x where x."org_id" = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."update_risk"(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = update_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row."category" := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row."cause" := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row."consequence" := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row."review_interval_months" := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update "better_supabase"."risks" x set "title" = v_row."title", "description" = v_row."description", "category" = v_row."category", "cause" = v_row."cause", "consequence" = v_row."consequence", "owner_id" = v_row."owner_id", "review_interval_months" = v_row."review_interval_months", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_risk"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_risk"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."assess_risk"(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_matrix "better_supabase"."risk_matrices"%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment "better_supabase"."risk_assessments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = assess_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.assess'), false) then
    raise exception 'not allowed to assess risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if v_row."status" = 'closed' then
    raise exception 'a closed risk can''t change' using errcode = '55000', hint = 'RISK_CLOSED';
  end if;
  select * into v_matrix from "better_supabase"."risk_matrices" x where x."id" = v_row."matrix_id";
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or residual_likelihood not between 1 and jsonb_array_length(v_matrix."likelihood_levels") or inherent_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") or residual_impact not between 1 and jsonb_array_length(v_matrix."impact_levels") then
    raise exception 'a level is out of range' using errcode = '22023', hint = 'RISK_LEVEL_OUT_OF_RANGE';
  end if;
  v_inherent := case when v_matrix."scoring" = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix."scoring" = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into "better_supabase"."risk_assessments" ("org_id", "risk_id", "inherent_likelihood", "inherent_impact", "inherent_score", "inherent_band", "residual_likelihood", "residual_impact", "residual_score", "residual_band", "rationale")
  values (v_row."org_id", v_row."id", inherent_likelihood, inherent_impact, v_inherent, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_inherent and (b ->> 'max')::integer >= v_inherent limit 1), residual_likelihood, residual_impact, v_residual, (select b ->> 'key' from jsonb_array_elements(v_matrix."bands") b where (b ->> 'min')::integer <= v_residual and (b ->> 'max')::integer >= v_residual limit 1), assess_risk.rationale)
  returning * into v_assessment;
  update "better_supabase"."risks" x set "inherent_likelihood" = inherent_likelihood, "inherent_impact" = inherent_impact, "inherent_score" = v_inherent, "inherent_band" = v_assessment."inherent_band", "residual_likelihood" = residual_likelihood, "residual_impact" = residual_impact, "residual_score" = v_residual, "residual_band" = v_assessment."residual_band", "current_assessment_id" = v_assessment."id", "status" = case when "status" = 'identified' then 'assessed' else "status" end, "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) from public, anon;
grant execute on function "better_supabase"."assess_risk"(uuid, integer, integer, integer, integer, text) to authenticated, service_role;

create or replace function "better_supabase"."set_risk_treatment"(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = set_risk_treatment.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.write'), false) then
    raise exception 'not allowed to change risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    raise exception 'the treatment is invalid' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if set_risk_treatment.treatment = 'accept' and not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.manage'), false) then
    raise exception 'accepting a risk needs risks.manage' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "treatment" = set_risk_treatment.treatment, "status" = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_risk_treatment"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."review_risk"(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = review_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.write'), false) then
    raise exception 'not allowed to review risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "next_review_on" = case when "review_interval_months" is null then "next_review_on" else current_date + make_interval(months => "review_interval_months") end, "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."close_risk"(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."risks" x where x."id" = close_risk.risk_id for update;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.manage'), false) then
    raise exception 'not allowed to close risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  update "better_supabase"."risks" x set "status" = 'closed', "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_risk"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_risk"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_risk"(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."risks"%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from "better_supabase"."risks" x where x."id" = get_risk.risk_id;
  if not found then
    raise exception 'risk not found' using errcode = 'P0002', hint = 'RISK_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'risks.read'), false) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'rationale', x."rationale", 'assessedAt', x."assessed_at") order by x."assessed_at" desc), '[]'::jsonb) into v_assessments from "better_supabase"."risk_assessments" x where x."risk_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'matrixId', v_row."matrix_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'inherentLikelihood', v_row."inherent_likelihood", 'inherentImpact', v_row."inherent_impact", 'inherentScore', v_row."inherent_score", 'inherentBand', v_row."inherent_band", 'residualLikelihood', v_row."residual_likelihood", 'residualImpact', v_row."residual_impact", 'residualScore', v_row."residual_score", 'residualBand', v_row."residual_band", 'currentAssessmentId', v_row."current_assessment_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('assessments', v_assessments);
end;
$$;
revoke execute on function "better_supabase"."get_risk"(uuid) from public, anon;
grant execute on function "better_supabase"."get_risk"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_risks"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'matrixId', x."matrix_id", 'number', x."number", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'inherentLikelihood', x."inherent_likelihood", 'inherentImpact', x."inherent_impact", 'inherentScore', x."inherent_score", 'inherentBand', x."inherent_band", 'residualLikelihood', x."residual_likelihood", 'residualImpact', x."residual_impact", 'residualScore', x."residual_score", 'residualBand', x."residual_band", 'currentAssessmentId', x."current_assessment_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."risks" x
  where x."org_id" = $1
    and x."org_id" in (select better_supabase.tenant_ids_with('risks.read'))
    and (not (filters ? 'category') or x."category" = filters ->> 'category')
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x."next_review_on" is not null and x."next_review_on" <= current_date))
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
$$;
revoke execute on function "better_supabase"."list_risks"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_risks"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."risk_heatmap"(tenant uuid, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', jsonb_build_object('id', m."id", 'organizationId', m."org_id", 'key', m."key", 'name', m."name", 'likelihoodLevels', m."likelihood_levels", 'impactLevels', m."impact_levels", 'bands', m."bands", 'scoring', m."scoring", 'isDefault', m."is_default"),
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x."inherent_likelihood" else x."residual_likelihood" end as l,
      case when $3 = 'inherent' then x."inherent_impact" else x."residual_impact" end as i,
      count(*) as c,
      jsonb_agg(x."id") as ids
    from "better_supabase"."risks" x
    where x."org_id" = $1 and x."status" <> 'closed' and x."org_id" in (select better_supabase.tenant_ids_with('risks.read'))
    group by 1, 2
  ) s
  cross join (select * from "better_supabase"."risk_matrices" where "id" = coalesce($2, (select "id" from "better_supabase"."risk_matrices" where "org_id" = $1 and "is_default" limit 1))) m
  group by m."id", m."org_id", m."key", m."name", m."likelihood_levels", m."impact_levels", m."bands", m."scoring", m."is_default"
$$;
revoke execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."risk_heatmap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_risk_reviews"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "better_supabase"."risks" x where x."status" <> 'closed' and x."next_review_on" is not null and x."next_review_on" <= current_date
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_risk_reviews"() from public, anon;
grant execute on function "better_supabase"."notify_due_risk_reviews"() to authenticated, service_role;

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
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_insert on "better_supabase"."risk_matrices" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_update on "better_supabase"."risk_matrices" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risk_matrices";
create policy bsb_tenant_scope_delete on "better_supabase"."risk_matrices" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."risks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."risks";
create policy bsb_tenant_scope_select on "better_supabase"."risks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risks";
create policy bsb_tenant_scope_insert on "better_supabase"."risks" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."risks";
create policy bsb_tenant_scope_update on "better_supabase"."risks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risks";
create policy bsb_tenant_scope_delete on "better_supabase"."risks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."risk_assessments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_select on "better_supabase"."risk_assessments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('risks.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_insert on "better_supabase"."risk_assessments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_update on "better_supabase"."risk_assessments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."risk_assessments";
create policy bsb_tenant_scope_delete on "better_supabase"."risk_assessments" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_145_risks.sql
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
