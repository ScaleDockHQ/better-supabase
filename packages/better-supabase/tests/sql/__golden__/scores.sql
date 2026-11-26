-- ==== alone: schema supabase/schemas/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block scores@1 managed
-- @bsb-hash sha256:158f3b007a6c075f44bbd01f94bbe666aaafbb09e076a320fc894102de256346
-- Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."score_models" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- lead, health, or the app's own key.
  "key" text not null constraint bsb_score_models_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_score_models_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text constraint bsb_score_models_description_check check ("description" is null or length("description") <= 2000),
  "subject_type" text not null constraint bsb_score_models_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  -- [{ id, label, conditions, points }]: a filter tree over the rules field
  -- catalog and the points a match adds.
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_models_rules_check check (jsonb_typeof("rules") = 'array'),
  -- [{ id, label, source, field, weight, cap }]: a number times its weight.
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_models_metrics_check check (jsonb_typeof("metrics") = 'array'),
  -- [{ label, min }], highest min first: the first band the score reaches.
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_models_bands_check check (jsonb_typeof("bands") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "key")
);
create index "score_models_subject_idx" on "better_supabase"."score_models" ("tenant_id", "subject_type");

create table "better_supabase"."score_model_versions" (
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "version" integer not null,
  "tenant_id" uuid not null,
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_rules_check check (jsonb_typeof("rules") = 'array'),
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_metrics_check check (jsonb_typeof("metrics") = 'array'),
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_bands_check check (jsonb_typeof("bands") = 'array'),
  "saved_by" uuid,
  "saved_at" timestamptz not null default now(),
  primary key ("model_id", "version")
);

create table "better_supabase"."scores" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "model_version" integer not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "score" numeric not null,
  "band" text,
  -- { rules: [{ id, label, matched, points }], metrics: [{ id, label, value, points }] }
  "breakdown" jsonb not null default '{}'::jsonb constraint bsb_scores_breakdown_check check (jsonb_typeof("breakdown") = 'object'),
  "is_current" boolean not null default true,
  "computed_at" timestamptz not null default now()
);
create unique index "scores_current_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id") where "is_current";
create index "scores_rank_idx" on "better_supabase"."scores" ("tenant_id", "model_id", "score" desc) where "is_current";
create index "scores_subject_idx" on "better_supabase"."scores" ("tenant_id", "subject_type", "subject_id") where "is_current";
create index "scores_history_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id", "computed_at" desc);

alter table "better_supabase"."score_models" enable row level security;
revoke all on "better_supabase"."score_models" from public, anon, authenticated;
grant select on "better_supabase"."score_models" to authenticated;
grant all on "better_supabase"."score_models" to service_role;
create policy bsb_score_models_read on "better_supabase"."score_models"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."score_model_versions" enable row level security;
revoke all on "better_supabase"."score_model_versions" from public, anon, authenticated;
grant select on "better_supabase"."score_model_versions" to authenticated;
grant all on "better_supabase"."score_model_versions" to service_role;
create policy bsb_score_model_versions_read on "better_supabase"."score_model_versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."scores" enable row level security;
revoke all on "better_supabase"."scores" from public, anon, authenticated;
grant select on "better_supabase"."scores" to authenticated;
grant all on "better_supabase"."scores" to service_role;
create policy bsb_scores_read on "better_supabase"."scores"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));

-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function "better_supabase"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = upsert_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = upsert_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (upsert_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

-- An organization's score models, by key, for one subject type when given.
-- Archived models stay out unless include_archived is true.

create or replace function "better_supabase"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

-- The organization's score models as a keyset page, by name (ADR 1077). Needs
-- scores.read. filters is { subjectType, enabled (each a value or a list),
-- archived (["true"] lists the archived ones), search (name, key), sort (name,
-- key, version), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_score_models"(uuid, jsonb) to authenticated, service_role;

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function "better_supabase"."get_score_model"(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."get_score_model"(uuid) to authenticated, service_role;


-- Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay. Needs scores.manage; archiving an archived model returns it unchanged.
create or replace function "better_supabase"."archive_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_score_model"(uuid) to authenticated, service_role;

-- Restores an archived score model; it keeps its enabled flag. Needs scores.manage; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_score_model"(uuid) to authenticated, service_role;

-- Removes a score model with its versions and scores for good; false when
-- there is none. Archive keeps them. permissions.purge gates it, falling back
-- to manage.

create or replace function "better_supabase"."purge_score_model"(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_score_model"(uuid) to authenticated, service_role;

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function "better_supabase"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := 0;
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$$;
revoke execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

-- A subject's current scores, one per model, by model key.
create or replace function "better_supabase"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_scores"(uuid, text, text) to authenticated, service_role;

-- A subject's scores under one model, newest first.
create or replace function "better_supabase"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function "better_supabase"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."score_models" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_models" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_models" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_models" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."score_model_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_model_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_model_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_model_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."scores" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."scores" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."scores" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."scores" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block scores@1 managed
-- @bsb-hash sha256:511d46d0a32dfa816359f6cdd473106f064380ecc9c898aa12deecd7ffe221f8
-- Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."score_models" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- lead, health, or the app's own key.
  "key" text not null constraint bsb_score_models_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_score_models_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text constraint bsb_score_models_description_check check ("description" is null or length("description") <= 2000),
  "subject_type" text not null constraint bsb_score_models_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  -- [{ id, label, conditions, points }]: a filter tree over the rules field
  -- catalog and the points a match adds.
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_models_rules_check check (jsonb_typeof("rules") = 'array'),
  -- [{ id, label, source, field, weight, cap }]: a number times its weight.
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_models_metrics_check check (jsonb_typeof("metrics") = 'array'),
  -- [{ label, min }], highest min first: the first band the score reaches.
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_models_bands_check check (jsonb_typeof("bands") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "key")
);
create index "score_models_subject_idx" on "better_supabase"."score_models" ("tenant_id", "subject_type");

create table "better_supabase"."score_model_versions" (
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "version" integer not null,
  "tenant_id" uuid not null,
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_rules_check check (jsonb_typeof("rules") = 'array'),
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_metrics_check check (jsonb_typeof("metrics") = 'array'),
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_bands_check check (jsonb_typeof("bands") = 'array'),
  "saved_by" uuid,
  "saved_at" timestamptz not null default now(),
  primary key ("model_id", "version")
);

create table "better_supabase"."scores" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "model_version" integer not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "score" numeric not null,
  "band" text,
  -- { rules: [{ id, label, matched, points }], metrics: [{ id, label, value, points }] }
  "breakdown" jsonb not null default '{}'::jsonb constraint bsb_scores_breakdown_check check (jsonb_typeof("breakdown") = 'object'),
  "is_current" boolean not null default true,
  "computed_at" timestamptz not null default now()
);
create unique index "scores_current_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id") where "is_current";
create index "scores_rank_idx" on "better_supabase"."scores" ("tenant_id", "model_id", "score" desc) where "is_current";
create index "scores_subject_idx" on "better_supabase"."scores" ("tenant_id", "subject_type", "subject_id") where "is_current";
create index "scores_history_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id", "computed_at" desc);

alter table "better_supabase"."score_models" enable row level security;
revoke all on "better_supabase"."score_models" from public, anon, authenticated;
grant select on "better_supabase"."score_models" to authenticated;
grant all on "better_supabase"."score_models" to service_role;
create policy bsb_score_models_read on "better_supabase"."score_models"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."score_model_versions" enable row level security;
revoke all on "better_supabase"."score_model_versions" from public, anon, authenticated;
grant select on "better_supabase"."score_model_versions" to authenticated;
grant all on "better_supabase"."score_model_versions" to service_role;
create policy bsb_score_model_versions_read on "better_supabase"."score_model_versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."scores" enable row level security;
revoke all on "better_supabase"."scores" from public, anon, authenticated;
grant select on "better_supabase"."scores" to authenticated;
grant all on "better_supabase"."scores" to service_role;
create policy bsb_scores_read on "better_supabase"."scores"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));

-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function "better_supabase"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = upsert_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field', 'votes')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field or votes), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = upsert_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (upsert_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    perform "better_supabase".emit_event('score_model.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.created',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  else
    perform "better_supabase".emit_event('score_model.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.updated',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

-- An organization's score models, by key, for one subject type when given.
-- Archived models stay out unless include_archived is true.

create or replace function "better_supabase"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

-- The organization's score models as a keyset page, by name (ADR 1077). Needs
-- scores.read. filters is { subjectType, enabled (each a value or a list),
-- archived (["true"] lists the archived ones), search (name, key), sort (name,
-- key, version), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_score_models"(uuid, jsonb) to authenticated, service_role;

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function "better_supabase"."get_score_model"(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."get_score_model"(uuid) to authenticated, service_role;


-- Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay. Needs scores.manage; archiving an archived model returns it unchanged.
create or replace function "better_supabase"."archive_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('score_model.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.archived',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'archived score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_score_model"(uuid) to authenticated, service_role;

-- Restores an archived score model; it keeps its enabled flag. Needs scores.manage; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('score_model.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.restored',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'restored score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_score_model"(uuid) to authenticated, service_role;

-- Removes a score model with its versions and scores for good; false when
-- there is none. Archive keeps them. permissions.purge gates it, falling back
-- to manage.

create or replace function "better_supabase"."purge_score_model"(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('score_model.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.purged',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'purged score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_score_model"(uuid) to authenticated, service_role;

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function "better_supabase"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := coalesce((select y."score" from "better_supabase"."reaction_scores" y where y."tenant_id" = compute_score.tenant and y."subject_type" = compute_score.subject_type and y."subject_id" = compute_score.subject_id), 0);
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  perform "better_supabase".emit_event('score.changed', jsonb_build_object('organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'previousScore', v_current."score", 'band', v_row."band", 'previousBand', v_current."band"), 'scores/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$$;
revoke execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

-- A subject's current scores, one per model, by model key.
create or replace function "better_supabase"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_scores"(uuid, text, text) to authenticated, service_role;

-- A subject's scores under one model, newest first.
create or replace function "better_supabase"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function "better_supabase"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."score_models" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_models" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_models" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_models" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."score_model_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_model_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_model_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_model_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."scores" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."scores" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."scores" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."scores" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.score_models deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"score_model","event_prefix":"score_model","archive_column":"archived_at"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block scores@1 managed
-- @bsb-hash sha256:4ca38e717e34d007b7f49048ba5470df134dca8b1c82d39d7ae62f017445b4be
-- Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges for role postgres in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on functions from public, anon, authenticated;
create table "app_private"."score_models" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- lead, health, or the app's own key.
  "key" text not null constraint bsb_score_models_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_score_models_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text constraint bsb_score_models_description_check check ("description" is null or length("description") <= 2000),
  "subject_type" text not null constraint bsb_score_models_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  -- [{ id, label, conditions, points }]: a filter tree over the rules field
  -- catalog and the points a match adds.
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_models_rules_check check (jsonb_typeof("rules") = 'array'),
  -- [{ id, label, source, field, weight, cap }]: a number times its weight.
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_models_metrics_check check (jsonb_typeof("metrics") = 'array'),
  -- [{ label, min }], highest min first: the first band the score reaches.
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_models_bands_check check (jsonb_typeof("bands") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "key")
);
create index "score_models_subject_idx" on "app_private"."score_models" ("tenant_id", "subject_type");

create table "app_private"."score_model_versions" (
  "model_id" uuid not null references "app_private"."score_models" ("id") on delete cascade,
  "version" integer not null,
  "tenant_id" uuid not null,
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_rules_check check (jsonb_typeof("rules") = 'array'),
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_metrics_check check (jsonb_typeof("metrics") = 'array'),
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_bands_check check (jsonb_typeof("bands") = 'array'),
  "saved_by" uuid,
  "saved_at" timestamptz not null default now(),
  primary key ("model_id", "version")
);

create table "app_private"."scores" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "model_id" uuid not null references "app_private"."score_models" ("id") on delete cascade,
  "model_version" integer not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "score" numeric not null,
  "band" text,
  -- { rules: [{ id, label, matched, points }], metrics: [{ id, label, value, points }] }
  "breakdown" jsonb not null default '{}'::jsonb constraint bsb_scores_breakdown_check check (jsonb_typeof("breakdown") = 'object'),
  "is_current" boolean not null default true,
  "computed_at" timestamptz not null default now()
);
create unique index "scores_current_idx" on "app_private"."scores" ("model_id", "subject_type", "subject_id") where "is_current";
create index "scores_rank_idx" on "app_private"."scores" ("tenant_id", "model_id", "score" desc) where "is_current";
create index "scores_subject_idx" on "app_private"."scores" ("tenant_id", "subject_type", "subject_id") where "is_current";
create index "scores_history_idx" on "app_private"."scores" ("model_id", "subject_type", "subject_id", "computed_at" desc);

alter table "app_private"."score_models" enable row level security;
revoke all on "app_private"."score_models" from public, anon, authenticated;
grant select on "app_private"."score_models" to authenticated;
grant all on "app_private"."score_models" to service_role;
create policy bsb_score_models_read on "app_private"."score_models"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "app_private"."score_model_versions" enable row level security;
revoke all on "app_private"."score_model_versions" from public, anon, authenticated;
grant select on "app_private"."score_model_versions" to authenticated;
grant all on "app_private"."score_model_versions" to service_role;
create policy bsb_score_model_versions_read on "app_private"."score_model_versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "app_private"."scores" enable row level security;
revoke all on "app_private"."scores" from public, anon, authenticated;
grant select on "app_private"."scores" to authenticated;
grant all on "app_private"."scores" to service_role;
create policy bsb_scores_read on "app_private"."scores"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));

-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function "app_private"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "app_private"."score_models";
  v_row "app_private"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "app_private"."score_models" x where x."id" = v_id and x."tenant_id" = upsert_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "app_private"."score_models" x where x."tenant_id" = upsert_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "app_private"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (upsert_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "app_private"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "app_private"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

-- An organization's score models, by key, for one subject type when given.
-- Archived models stay out unless include_archived is true.

create or replace function "app_private"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "app_private"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "app_private"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

-- The organization's score models as a keyset page, by name (ADR 1077). Needs
-- scores.read. filters is { subjectType, enabled (each a value or a list),
-- archived (["true"] lists the archived ones), search (name, key), sort (name,
-- key, version), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "app_private"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."page_score_models"(uuid, jsonb) to authenticated, service_role;

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function "app_private"."get_score_model"(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."score_models";
begin
  select * into v_row from "app_private"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "app_private"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."get_score_model"(uuid) from public, anon;
grant execute on function "app_private"."get_score_model"(uuid) to authenticated, service_role;


-- Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay. Needs scores.manage; archiving an archived model returns it unchanged.
create or replace function "app_private"."archive_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "app_private"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."archive_score_model"(uuid) from public, anon;
grant execute on function "app_private"."archive_score_model"(uuid) to authenticated, service_role;

-- Restores an archived score model; it keeps its enabled flag. Needs scores.manage; restoring one that is not archived returns it unchanged.
create or replace function "app_private"."restore_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "app_private"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "app_private"."restore_score_model"(uuid) from public, anon;
grant execute on function "app_private"."restore_score_model"(uuid) to authenticated, service_role;

-- Removes a score model with its versions and scores for good; false when
-- there is none. Archive keeps them. permissions.purge gates it, falling back
-- to manage.

create or replace function "app_private"."purge_score_model"(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "app_private"."score_models" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."purge_score_model"(uuid) from public, anon;
grant execute on function "app_private"."purge_score_model"(uuid) to authenticated, service_role;

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function "app_private"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model "app_private"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "app_private"."scores";
  v_row "app_private"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "app_private"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := 0;
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "app_private"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "app_private"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "app_private"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$$;
revoke execute on function "app_private"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "app_private"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

-- A subject's current scores, one per model, by model key.
create or replace function "app_private"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "app_private"."scores" x join "app_private"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "app_private"."subject_scores"(uuid, text, text) to authenticated, service_role;

-- A subject's scores under one model, newest first.
create or replace function "app_private"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "app_private"."scores" x join "app_private"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "app_private"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function "app_private"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "app_private"."scores" x join "app_private"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "app_private"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."score_models" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."score_models" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."score_models" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."score_models" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."score_model_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."score_model_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."score_model_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."score_model_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."scores" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."scores" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."scores" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."scores" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block scores@1 managed
-- @bsb-hash sha256:8d8858ffa5077b5674b06b1c7363b29feda5100a0750b8d14dd4b361c0b28d85
-- Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."score_models" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- lead, health, or the app's own key.
  "key" text not null constraint bsb_score_models_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_score_models_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text constraint bsb_score_models_description_check check ("description" is null or length("description") <= 2000),
  "subject_type" text not null constraint bsb_score_models_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  -- [{ id, label, conditions, points }]: a filter tree over the rules field
  -- catalog and the points a match adds.
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_models_rules_check check (jsonb_typeof("rules") = 'array'),
  -- [{ id, label, source, field, weight, cap }]: a number times its weight.
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_models_metrics_check check (jsonb_typeof("metrics") = 'array'),
  -- [{ label, min }], highest min first: the first band the score reaches.
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_models_bands_check check (jsonb_typeof("bands") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("tenant_id", "key")
);
create index "score_models_subject_idx" on "better_supabase"."score_models" ("tenant_id", "subject_type");

create table "better_supabase"."score_model_versions" (
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "version" integer not null,
  "tenant_id" uuid not null,
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_rules_check check (jsonb_typeof("rules") = 'array'),
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_metrics_check check (jsonb_typeof("metrics") = 'array'),
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_bands_check check (jsonb_typeof("bands") = 'array'),
  "saved_by" uuid,
  "saved_at" timestamptz not null default now(),
  primary key ("model_id", "version")
);

create table "better_supabase"."scores" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "model_version" integer not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "score" numeric not null,
  "band" text,
  -- { rules: [{ id, label, matched, points }], metrics: [{ id, label, value, points }] }
  "breakdown" jsonb not null default '{}'::jsonb constraint bsb_scores_breakdown_check check (jsonb_typeof("breakdown") = 'object'),
  "is_current" boolean not null default true,
  "computed_at" timestamptz not null default now()
);
create unique index "scores_current_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id") where "is_current";
create index "scores_rank_idx" on "better_supabase"."scores" ("tenant_id", "model_id", "score" desc) where "is_current";
create index "scores_subject_idx" on "better_supabase"."scores" ("tenant_id", "subject_type", "subject_id") where "is_current";
create index "scores_history_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id", "computed_at" desc);

alter table "better_supabase"."score_models" enable row level security;
revoke all on "better_supabase"."score_models" from public, anon, authenticated;
grant select on "better_supabase"."score_models" to authenticated;
grant all on "better_supabase"."score_models" to service_role;
create policy bsb_score_models_read on "better_supabase"."score_models"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."score_model_versions" enable row level security;
revoke all on "better_supabase"."score_model_versions" from public, anon, authenticated;
grant select on "better_supabase"."score_model_versions" to authenticated;
grant all on "better_supabase"."score_model_versions" to service_role;
create policy bsb_score_model_versions_read on "better_supabase"."score_model_versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."scores" enable row level security;
revoke all on "better_supabase"."scores" from public, anon, authenticated;
grant select on "better_supabase"."scores" to authenticated;
grant all on "better_supabase"."scores" to service_role;
create policy bsb_scores_read on "better_supabase"."scores"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));

-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function "better_supabase"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = upsert_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = upsert_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (upsert_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

-- An organization's score models, by key, for one subject type when given.
-- Archived models stay out unless include_archived is true.

create or replace function "better_supabase"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

-- The organization's score models as a keyset page, by name (ADR 1077). Needs
-- scores.read. filters is { subjectType, enabled (each a value or a list),
-- archived (["true"] lists the archived ones), search (name, key), sort (name,
-- key, version), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_score_models"(uuid, jsonb) to authenticated, service_role;

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function "better_supabase"."get_score_model"(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."get_score_model"(uuid) to authenticated, service_role;


-- Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay. Needs scores.manage; archiving an archived model returns it unchanged.
create or replace function "better_supabase"."archive_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_score_model"(uuid) to authenticated, service_role;

-- Restores an archived score model; it keeps its enabled flag. Needs scores.manage; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_score_model"(uuid) to authenticated, service_role;

-- Removes a score model with its versions and scores for good; false when
-- there is none. Archive keeps them. permissions.purge gates it, falling back
-- to manage.

create or replace function "better_supabase"."purge_score_model"(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_score_model"(uuid) to authenticated, service_role;

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function "better_supabase"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := 0;
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$$;
revoke execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

-- A subject's current scores, one per model, by model key.
create or replace function "better_supabase"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_scores"(uuid, text, text) to authenticated, service_role;

-- A subject's scores under one model, newest first.
create or replace function "better_supabase"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function "better_supabase"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."score_models" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_models" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_models" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_models" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."score_model_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_model_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_model_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_model_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."scores" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."scores" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."scores" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."scores" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.scores.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_score_model"($1, $2) $$;
revoke execute on function "api"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "api"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_score_models"($1, $2, $3) $$;
revoke execute on function "api"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "api"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_score_models"($1, $2) $$;
revoke execute on function "api"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_score_models"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_score_model"(model_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_score_model"($1) $$;
revoke execute on function "api"."get_score_model"(uuid) from public, anon;
grant execute on function "api"."get_score_model"(uuid) to authenticated, service_role;

create or replace function "api"."archive_score_model"(model_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_score_model"($1) $$;
revoke execute on function "api"."archive_score_model"(uuid) from public, anon;
grant execute on function "api"."archive_score_model"(uuid) to authenticated, service_role;

create or replace function "api"."restore_score_model"(model_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_score_model"($1) $$;
revoke execute on function "api"."restore_score_model"(uuid) from public, anon;
grant execute on function "api"."restore_score_model"(uuid) to authenticated, service_role;

create or replace function "api"."purge_score_model"(model_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_score_model"($1) $$;
revoke execute on function "api"."purge_score_model"(uuid) from public, anon;
grant execute on function "api"."purge_score_model"(uuid) to authenticated, service_role;

create or replace function "api"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."compute_score"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "api"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

create or replace function "api"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_scores"($1, $2, $3) $$;
revoke execute on function "api"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "api"."subject_scores"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."score_history"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "api"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

create or replace function "api"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."top_scores"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "api"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block scores@1 managed
-- @bsb-hash sha256:37816735e0978a149636c99580fdde72f21877397d067c56f1e2abdee9c47b92
-- Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.score_models is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."score_models" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."score_models" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."score_models" add column if not exists "key" text constraint bsb_score_models_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."score_models" add column if not exists "name" text constraint bsb_score_models_name_check check (length("name") >= 1 and length("name") <= 200);
alter table "better_supabase"."score_models" add column if not exists "description" text constraint bsb_score_models_description_check check ("description" is null or length("description") <= 2000);
alter table "better_supabase"."score_models" add column if not exists "subject_type" text constraint bsb_score_models_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."score_models" add column if not exists "rules" jsonb not null default '[]'::jsonb constraint bsb_score_models_rules_check check (jsonb_typeof("rules") = 'array');
alter table "better_supabase"."score_models" add column if not exists "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_models_metrics_check check (jsonb_typeof("metrics") = 'array');
alter table "better_supabase"."score_models" add column if not exists "bands" jsonb not null default '[]'::jsonb constraint bsb_score_models_bands_check check (jsonb_typeof("bands") = 'array');
alter table "better_supabase"."score_models" add column if not exists "enabled" boolean not null default true;
alter table "better_supabase"."score_models" add column if not exists "version" integer not null default 1;
alter table "better_supabase"."score_models" add column if not exists "created_by" uuid;
alter table "better_supabase"."score_models" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."score_models" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."score_models" add column if not exists "archived_at" timestamptz;
create index if not exists "score_models_subject_idx" on "better_supabase"."score_models" ("tenant_id", "subject_type");
alter table "better_supabase"."score_models" add column if not exists "archived_at" timestamptz;

-- better_supabase.score_model_versions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."score_model_versions" add column if not exists "model_id" uuid references "better_supabase"."score_models" ("id") on delete cascade;
alter table "better_supabase"."score_model_versions" add column if not exists "version" integer;
alter table "better_supabase"."score_model_versions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."score_model_versions" add column if not exists "rules" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_rules_check check (jsonb_typeof("rules") = 'array');
alter table "better_supabase"."score_model_versions" add column if not exists "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_metrics_check check (jsonb_typeof("metrics") = 'array');
alter table "better_supabase"."score_model_versions" add column if not exists "bands" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_bands_check check (jsonb_typeof("bands") = 'array');
alter table "better_supabase"."score_model_versions" add column if not exists "saved_by" uuid;
alter table "better_supabase"."score_model_versions" add column if not exists "saved_at" timestamptz not null default now();
create unique index if not exists "bsb_score_model_versions_version_key" on "better_supabase"."score_model_versions" ("model_id", "version");

-- better_supabase.scores is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."scores" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."scores" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."scores" add column if not exists "model_id" uuid references "better_supabase"."score_models" ("id") on delete cascade;
alter table "better_supabase"."scores" add column if not exists "model_version" integer;
alter table "better_supabase"."scores" add column if not exists "subject_type" text;
alter table "better_supabase"."scores" add column if not exists "subject_id" text;
alter table "better_supabase"."scores" add column if not exists "score" numeric;
alter table "better_supabase"."scores" add column if not exists "band" text;
alter table "better_supabase"."scores" add column if not exists "breakdown" jsonb not null default '{}'::jsonb constraint bsb_scores_breakdown_check check (jsonb_typeof("breakdown") = 'object');
alter table "better_supabase"."scores" add column if not exists "is_current" boolean not null default true;
alter table "better_supabase"."scores" add column if not exists "computed_at" timestamptz not null default now();
create unique index if not exists "scores_current_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id") where "is_current";
create index if not exists "scores_rank_idx" on "better_supabase"."scores" ("tenant_id", "model_id", "score" desc) where "is_current";
create index if not exists "scores_subject_idx" on "better_supabase"."scores" ("tenant_id", "subject_type", "subject_id") where "is_current";
create index if not exists "scores_history_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id", "computed_at" desc);

alter table "better_supabase"."score_models" enable row level security;
grant select on "better_supabase"."score_models" to authenticated;
grant all on "better_supabase"."score_models" to service_role;
create policy bsb_score_models_select on "better_supabase"."score_models"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."score_model_versions" enable row level security;
grant select on "better_supabase"."score_model_versions" to authenticated;
grant all on "better_supabase"."score_model_versions" to service_role;
create policy bsb_score_model_versions_select on "better_supabase"."score_model_versions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."scores" enable row level security;
grant select on "better_supabase"."scores" to authenticated;
grant all on "better_supabase"."scores" to service_role;
create policy bsb_scores_select on "better_supabase"."scores"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')));

-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function "better_supabase"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = upsert_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = upsert_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (upsert_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

-- An organization's score models, by key, for one subject type when given.
-- Archived models stay out unless include_archived is true.

create or replace function "better_supabase"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

-- The organization's score models as a keyset page, by name (ADR 1077). Needs
-- scores.read. filters is { subjectType, enabled (each a value or a list),
-- archived (["true"] lists the archived ones), search (name, key), sort (name,
-- key, version), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."tenant_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_score_models"(uuid, jsonb) to authenticated, service_role;

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function "better_supabase"."get_score_model"(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."get_score_model"(uuid) to authenticated, service_role;


-- Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay. Needs scores.manage; archiving an archived model returns it unchanged.
create or replace function "better_supabase"."archive_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_score_model"(uuid) to authenticated, service_role;

-- Restores an archived score model; it keeps its enabled flag. Needs scores.manage; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_score_model"(uuid) to authenticated, service_role;

-- Removes a score model with its versions and scores for good; false when
-- there is none. Archive keeps them. permissions.purge gates it, falling back
-- to manage.

create or replace function "better_supabase"."purge_score_model"(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_score_model"(uuid) to authenticated, service_role;

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function "better_supabase"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := 0;
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$$;
revoke execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

-- A subject's current scores, one per model, by model key.
create or replace function "better_supabase"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_scores"(uuid, text, text) to authenticated, service_role;

-- A subject's scores under one model, newest first.
create or replace function "better_supabase"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function "better_supabase"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."score_models" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_models" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_models" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_models" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."score_model_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_model_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_model_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_model_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."scores" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."scores" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."scores" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."scores" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block scores@1 managed
-- @bsb-hash sha256:13a9cc9680362fb1694222e21246584308408688fbb672d8a56ef583c04bde77
-- Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."score_models" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  -- lead, health, or the app's own key.
  "key" text not null constraint bsb_score_models_key_check check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_score_models_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text constraint bsb_score_models_description_check check ("description" is null or length("description") <= 2000),
  "subject_type" text not null constraint bsb_score_models_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  -- [{ id, label, conditions, points }]: a filter tree over the rules field
  -- catalog and the points a match adds.
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_models_rules_check check (jsonb_typeof("rules") = 'array'),
  -- [{ id, label, source, field, weight, cap }]: a number times its weight.
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_models_metrics_check check (jsonb_typeof("metrics") = 'array'),
  -- [{ label, min }], highest min first: the first band the score reaches.
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_models_bands_check check (jsonb_typeof("bands") = 'array'),
  "enabled" boolean not null default true,
  "version" integer not null default 1,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "archived_at" timestamptz,
  unique ("org_id", "key")
);
create index "score_models_subject_idx" on "better_supabase"."score_models" ("org_id", "subject_type");

create table "better_supabase"."score_model_versions" (
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "version" integer not null,
  "org_id" uuid not null,
  "rules" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_rules_check check (jsonb_typeof("rules") = 'array'),
  "metrics" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_metrics_check check (jsonb_typeof("metrics") = 'array'),
  "bands" jsonb not null default '[]'::jsonb constraint bsb_score_model_versions_bands_check check (jsonb_typeof("bands") = 'array'),
  "saved_by" uuid,
  "saved_at" timestamptz not null default now(),
  primary key ("model_id", "version")
);

create table "better_supabase"."scores" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "model_id" uuid not null references "better_supabase"."score_models" ("id") on delete cascade,
  "model_version" integer not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "score" numeric not null,
  "band" text,
  -- { rules: [{ id, label, matched, points }], metrics: [{ id, label, value, points }] }
  "breakdown" jsonb not null default '{}'::jsonb constraint bsb_scores_breakdown_check check (jsonb_typeof("breakdown") = 'object'),
  "is_current" boolean not null default true,
  "computed_at" timestamptz not null default now()
);
create unique index "scores_current_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id") where "is_current";
create index "scores_rank_idx" on "better_supabase"."scores" ("org_id", "model_id", "score" desc) where "is_current";
create index "scores_subject_idx" on "better_supabase"."scores" ("org_id", "subject_type", "subject_id") where "is_current";
create index "scores_history_idx" on "better_supabase"."scores" ("model_id", "subject_type", "subject_id", "computed_at" desc);

alter table "better_supabase"."score_models" enable row level security;
revoke all on "better_supabase"."score_models" from public, anon, authenticated;
grant select on "better_supabase"."score_models" to authenticated;
grant all on "better_supabase"."score_models" to service_role;
create policy bsb_score_models_read on "better_supabase"."score_models"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."score_model_versions" enable row level security;
revoke all on "better_supabase"."score_model_versions" from public, anon, authenticated;
grant select on "better_supabase"."score_model_versions" to authenticated;
grant all on "better_supabase"."score_model_versions" to service_role;
create policy bsb_score_model_versions_read on "better_supabase"."score_model_versions"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('scores.read')));
alter table "better_supabase"."scores" enable row level security;
revoke all on "better_supabase"."scores" from public, anon, authenticated;
grant select on "better_supabase"."scores" to authenticated;
grant all on "better_supabase"."scores" to service_role;
create policy bsb_scores_read on "better_supabase"."scores"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('scores.read')));

-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function "better_supabase"."upsert_score_model"(tenant uuid, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."org_id" = upsert_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if v_old."archived_at" is not null then
      raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."org_id" = upsert_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("org_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (upsert_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."org_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'archivedAt', v_old."archived_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "org_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."org_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_score_model"(uuid, jsonb) to authenticated, service_role;

-- An organization's score models, by key, for one subject type when given.
-- Archived models stay out unless include_archived is true.

create or replace function "better_supabase"."list_score_models"(tenant uuid, subject_type text default null, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."org_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
      and (coalesce(list_score_models.include_archived, false) or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_score_models"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_score_models"(uuid, text, boolean) to authenticated, service_role;

-- The organization's score models as a keyset page, by name (ADR 1077). Needs
-- scores.read. filters is { subjectType, enabled (each a value or a list),
-- archived (["true"] lists the archived ones), search (name, key), sort (name,
-- key, version), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_score_models"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_score_models.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'enabled') then
      raise exception 'facet is one of subjectType, enabled' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key', 'version') then
    raise exception 'sort is one of name, key, version' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."key" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."version" <= (v_after ->> 0)::integer and ((x."version" < (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."version" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."score_models" x
      where x."org_id" = page_score_models.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_score_models"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_score_models"(uuid, jsonb) to authenticated, service_role;

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function "better_supabase"."get_score_model"(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."get_score_model"(uuid) to authenticated, service_role;


-- Archives a score model: it leaves the lists, subject_scores and top_scores, and compute_score refuses it. Its versions and scores stay. Needs scores.manage; archiving an archived model returns it unchanged.
create or replace function "better_supabase"."archive_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = archive_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_score_model"(uuid) to authenticated, service_role;

-- Restores an archived score model; it keeps its enabled flag. Needs scores.manage; restoring one that is not archived returns it unchanged.
create or replace function "better_supabase"."restore_score_model"(model_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = restore_score_model.model_id for update;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."score_models" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_score_model"(uuid) to authenticated, service_role;

-- Removes a score model with its versions and scores for good; false when
-- there is none. Archive keeps them. permissions.purge gates it, falling back
-- to manage.

create or replace function "better_supabase"."purge_score_model"(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = purge_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'scores.manage'), false)) then
    raise exception 'not allowed to purge score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_score_model"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_score_model"(uuid) to authenticated, service_role;

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function "better_supabase"."compute_score"(tenant uuid, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."org_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if v_model."archived_at" is not null then
    raise exception 'the score model is archived; restore it first' using errcode = '55000', hint = 'SCORES_MODEL_ARCHIVED';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := 0;
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."org_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("org_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
end;
$$;
revoke execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) to authenticated, service_role;

-- A subject's current scores, one per model, by model key.
create or replace function "better_supabase"."subject_scores"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."org_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
      and y."archived_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_scores"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_scores"(uuid, text, text) to authenticated, service_role;

-- A subject's scores under one model, newest first.
create or replace function "better_supabase"."score_history"(tenant uuid, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."org_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."org_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."score_history"(uuid, text, text, text, integer) to authenticated, service_role;

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function "better_supabase"."top_scores"(tenant uuid, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."org_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."org_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
      and y."archived_at" is null
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) from public, anon;
grant execute on function "better_supabase"."top_scores"(uuid, text, text, numeric, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."score_models" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_models" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_models" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_models" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."score_model_versions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."score_model_versions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."score_model_versions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."score_model_versions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."scores" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('scores.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."scores" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."scores" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."scores" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_115_scores.sql
-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:6f7c9cc86a08b5480b4f7941a14408ff700c102e1241a9529bcf6e776cacf087
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
