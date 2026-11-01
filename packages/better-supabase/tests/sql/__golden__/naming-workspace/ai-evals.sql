-- ==== schema supabase/schemas/900_better_supabase_171_ai_evals.sql
-- better-supabase module: ai-evals
-- @bsb-block ai-evals@1 managed
-- @bsb-hash sha256:eed7c87200ccfc4f09d751a098a3862183fdd52523a9ad3beefd26c6f5f63b26
-- Evaluation datasets of inputs and expected outputs (imported or taken from rated ai-chat replies), runs against a prompt version and model, a score per scorer and item, and a regression compare between two runs; only the service role reads and writes them.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eval_datasets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eval_datasets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eval_datasets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eval_datasets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eval_datasets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eval_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eval_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eval_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eval_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eval_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Evaluation datasets and runs. A dataset holds items (an input and, when
-- known, the expected output); a run replays the items against one prompt
-- version and model and keeps a score per scorer for each item. Inputs and
-- outputs can hold user content, so only the service role reads and writes
-- them.
create table if not exists "better_supabase"."eval_datasets" (
  "id" uuid primary key default gen_random_uuid(),
  "workspace_id" uuid,
  "name" text not null check ("name" ~ '^[a-z0-9][a-z0-9_.:/-]{0,127}$'),
  "description" text check (length("description") <= 2000),
  "created_at" timestamptz not null default now()
);
create unique index if not exists "bsb_eval_datasets_key" on "better_supabase"."eval_datasets" ((coalesce("workspace_id"::text, '')), "name");
alter table "better_supabase"."eval_datasets" enable row level security;
revoke all on "better_supabase"."eval_datasets" from public, anon, authenticated;
grant all on "better_supabase"."eval_datasets" to service_role;

create table if not exists "better_supabase"."eval_items" (
  "id" uuid primary key default gen_random_uuid(),
  "dataset_id" uuid not null references "better_supabase"."eval_datasets" ("id") on delete cascade,
  "input" jsonb not null,
  "expected" jsonb,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "source_chat_id" text,
  "source_message_id" text,
  "created_at" timestamptz not null default now()
);
create index if not exists "eval_items_dataset_idx" on "better_supabase"."eval_items" ("dataset_id", "id");
create unique index if not exists "bsb_eval_items_source_key" on "better_supabase"."eval_items" ("dataset_id", "source_chat_id", "source_message_id") where "source_chat_id" is not null;
alter table "better_supabase"."eval_items" enable row level security;
revoke all on "better_supabase"."eval_items" from public, anon, authenticated;
grant all on "better_supabase"."eval_items" to service_role;

create table if not exists "better_supabase"."eval_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "dataset_id" uuid not null references "better_supabase"."eval_datasets" ("id") on delete cascade,
  "workspace_id" uuid,
  "prompt_name" text not null,
  "prompt_version" integer not null check ("prompt_version" >= 1),
  "model" text not null,
  "scorers" jsonb not null default '[]'::jsonb check (jsonb_typeof("scorers") = 'array'),
  "status" text not null default 'running' check ("status" in ('running', 'completed', 'failed', 'cancelled')),
  "summary" jsonb,
  "created_at" timestamptz not null default now(),
  "finished_at" timestamptz
);
create index if not exists "eval_runs_dataset_idx" on "better_supabase"."eval_runs" ("dataset_id", "created_at" desc);
alter table "better_supabase"."eval_runs" enable row level security;
revoke all on "better_supabase"."eval_runs" from public, anon, authenticated;
grant all on "better_supabase"."eval_runs" to service_role;

create table if not exists "better_supabase"."eval_results" (
  "run_id" uuid not null references "better_supabase"."eval_runs" ("id") on delete cascade,
  "item_id" uuid not null references "better_supabase"."eval_items" ("id") on delete cascade,
  "output" text,
  "scores" jsonb not null default '{}'::jsonb check (jsonb_typeof("scores") = 'object'),
  "passed" boolean not null,
  "error" text,
  "latency_ms" integer check ("latency_ms" >= 0),
  "created_at" timestamptz not null default now(),
  primary key ("run_id", "item_id")
);
create index if not exists "eval_results_item_idx" on "better_supabase"."eval_results" ("item_id");
alter table "better_supabase"."eval_results" enable row level security;
revoke all on "better_supabase"."eval_results" from public, anon, authenticated;
grant all on "better_supabase"."eval_results" to service_role;

-- Creates a dataset, or returns the one with that name for the tenant.
create or replace function "better_supabase"."create_eval_dataset"(name text, tenant uuid default null, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_datasets"%rowtype;
begin
  insert into "better_supabase"."eval_datasets" ("workspace_id", "name", "description")
  values (create_eval_dataset.tenant, create_eval_dataset.name, create_eval_dataset.description)
  on conflict ((coalesce("workspace_id"::text, '')), "name") do update set
    "description" = coalesce(excluded."description", "better_supabase"."eval_datasets"."description")
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."workspace_id", 'name', v_row."name", 'description', v_row."description", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_eval_dataset"(text, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."create_eval_dataset"(text, uuid, text) to service_role;

-- Adds items, each an object with input and optionally expected and
-- metadata. Returns the number added; a dataset holds at most 5000.
create or replace function "better_supabase"."add_eval_items"(dataset uuid, items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  if not exists (select 1 from "better_supabase"."eval_datasets" x where x."id" = add_eval_items.dataset) then
    raise exception 'No eval dataset %', add_eval_items.dataset using errcode = 'P0002', hint = 'EVAL_DATASET_NOT_FOUND';
  end if;
  if jsonb_typeof(add_eval_items.items) is distinct from 'array' then
    raise exception 'items must be a JSON array' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(add_eval_items.items) e where jsonb_typeof(e.value) <> 'object' or not (e.value ? 'input')) then
    raise exception 'every item needs an input' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  if (select count(*) from "better_supabase"."eval_items" x where x."dataset_id" = add_eval_items.dataset) + jsonb_array_length(add_eval_items.items) > 5000 then
    raise exception 'A dataset holds at most 5000 items' using errcode = '54000', hint = 'EVAL_DATASET_FULL';
  end if;
  insert into "better_supabase"."eval_items" ("dataset_id", "input", "expected", "metadata")
  select add_eval_items.dataset, e.value -> 'input', e.value -> 'expected', coalesce(e.value -> 'metadata', '{}'::jsonb)
  from jsonb_array_elements(add_eval_items.items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."add_eval_items"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."add_eval_items"(uuid, jsonb) to service_role;

-- Needs the ai-chat block, which is not installed here.
create or replace function "better_supabase"."add_eval_items_from_feedback"(dataset uuid, rating integer default -1, since timestamptz default null, max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'add_eval_items_from_feedback needs the ai-chat block' using errcode = '55000', hint = 'EVAL_FEEDBACK_UNAVAILABLE';
end;
$$;
revoke execute on function "better_supabase"."add_eval_items_from_feedback"(uuid, integer, timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."add_eval_items_from_feedback"(uuid, integer, timestamptz, integer) to service_role;

-- The items of a dataset in id order after the given id. With pending_run,
-- only the items that run has no result for yet, so a job can resume.
create or replace function "better_supabase"."list_eval_items"(dataset uuid, pending_run uuid default null, after uuid default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', p."id", 'dataset_id', p."dataset_id", 'input', p."input", 'expected', p."expected", 'metadata', p."metadata", 'source_chat_id', p."source_chat_id", 'source_message_id', p."source_message_id", 'created_at', p."created_at") order by p."id"), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."eval_items" x
      where x."dataset_id" = list_eval_items.dataset
        and (list_eval_items.after is null or x."id" > list_eval_items.after)
        and (list_eval_items.pending_run is null or not exists (
          select 1 from "better_supabase"."eval_results" y where y."run_id" = list_eval_items.pending_run and y."item_id" = x."id"
        ))
      order by x."id"
      limit least(greatest(coalesce(list_eval_items.max_rows, 100), 1), 1000)
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."list_eval_items"(uuid, uuid, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_eval_items"(uuid, uuid, uuid, integer) to service_role;

-- Starts a run of a dataset against one prompt version and model. scorers
-- describes the scorers the run uses (name and kind) and is kept with it.
create or replace function "better_supabase"."create_eval_run"(dataset uuid, prompt_name text, prompt_version integer, model text, scorers jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dataset "better_supabase"."eval_datasets"%rowtype;
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  select x.* into v_dataset from "better_supabase"."eval_datasets" x where x."id" = create_eval_run.dataset;
  if not found then
    raise exception 'No eval dataset %', create_eval_run.dataset using errcode = 'P0002', hint = 'EVAL_DATASET_NOT_FOUND';
  end if;
  insert into "better_supabase"."eval_runs" ("dataset_id", "workspace_id", "prompt_name", "prompt_version", "model", "scorers")
  values (create_eval_run.dataset, v_dataset."workspace_id", create_eval_run.prompt_name, create_eval_run.prompt_version, create_eval_run.model, coalesce(create_eval_run.scorers, '[]'::jsonb))
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'organization_id', v_row."workspace_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$$;
revoke execute on function "better_supabase"."create_eval_run"(uuid, text, integer, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."create_eval_run"(uuid, text, integer, text, jsonb) to service_role;

-- Stores the output and scores of one item in a running run, replacing an
-- earlier result so a retried job is safe. scores maps a scorer name to
-- { score, passed, reason }; the result passes when there is no error and
-- every scorer passed.
create or replace function "better_supabase"."record_eval_result"(run uuid, item uuid, output text default null, scores jsonb default '{}'::jsonb, error text default null, latency_ms integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run "better_supabase"."eval_runs"%rowtype;
  v_row "better_supabase"."eval_results"%rowtype;
  v_scores jsonb := coalesce(record_eval_result.scores, '{}'::jsonb);
begin
  select x.* into v_run from "better_supabase"."eval_runs" x where x."id" = record_eval_result.run;
  if not found then
    raise exception 'No eval run %', record_eval_result.run using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'Eval run % is closed', record_eval_result.run using errcode = '55000', hint = 'EVAL_RUN_CLOSED';
  end if;
  if not exists (select 1 from "better_supabase"."eval_items" x where x."id" = record_eval_result.item and x."dataset_id" = v_run."dataset_id") then
    raise exception 'No eval item %', record_eval_result.item using errcode = 'P0002', hint = 'EVAL_ITEM_NOT_FOUND';
  end if;
  if jsonb_typeof(v_scores) <> 'object' then
    raise exception 'scores must be a JSON object' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  insert into "better_supabase"."eval_results" ("run_id", "item_id", "output", "scores", "passed", "error", "latency_ms")
  values (record_eval_result.run, record_eval_result.item, record_eval_result.output, v_scores,
    record_eval_result.error is null and not exists (select 1 from jsonb_each(v_scores) e where (e.value ->> 'passed') is distinct from 'true'),
    record_eval_result.error, record_eval_result.latency_ms)
  on conflict ("run_id", "item_id") do update set
    "output" = excluded."output", "scores" = excluded."scores", "passed" = excluded."passed",
    "error" = excluded."error", "latency_ms" = excluded."latency_ms", "created_at" = now()
  returning * into v_row;
  return jsonb_build_object('run_id', v_row."run_id", 'item_id', v_row."item_id", 'output', v_row."output", 'scores', v_row."scores", 'passed', v_row."passed", 'error', v_row."error", 'latency_ms', v_row."latency_ms", 'created_at', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_eval_result"(uuid, uuid, text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."record_eval_result"(uuid, uuid, text, jsonb, text, integer) to service_role;

-- The totals of a run: results, passed, failed, errored, the pass rate and the
-- average score and pass rate per scorer.
create or replace function "better_supabase"."eval_run_summary"(run uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'total', count(*),
    'passed', count(*) filter (where x."passed"),
    'failed', count(*) filter (where not x."passed" and x."error" is null),
    'errored', count(*) filter (where x."error" is not null),
    'passRate', coalesce(round(avg(case when x."passed" then 1 else 0 end), 4), 0),
    'scorers', coalesce((
      select jsonb_object_agg(t.name, jsonb_build_object('avg', t.mean, 'passRate', t.rate))
      from (
        select e.key as name, round(avg((e.value ->> 'score')::numeric), 4) as mean,
          round(avg(case when (e.value ->> 'passed') = 'true' then 1 else 0 end), 4) as rate
        from "better_supabase"."eval_results" y, jsonb_each(y."scores") e
        where y."run_id" = eval_run_summary.run
        group by e.key
      ) t
    ), '{}'::jsonb)
  )
  from "better_supabase"."eval_results" x where x."run_id" = eval_run_summary.run;
$$;
revoke execute on function "better_supabase"."eval_run_summary"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."eval_run_summary"(uuid) to service_role;

-- Closes a running run (completed, failed or cancelled) and stores its summary.
create or replace function "better_supabase"."finish_eval_run"(run uuid, status text default 'completed')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  if finish_eval_run.status not in ('completed', 'failed', 'cancelled') then
    raise exception 'status must be completed, failed or cancelled' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  update "better_supabase"."eval_runs" x set "status" = finish_eval_run.status, "summary" = "better_supabase"."eval_run_summary"(finish_eval_run.run), "finished_at" = now()
  where x."id" = finish_eval_run.run and x."status" = 'running'
  returning * into v_row;
  if not found then
    select x.* into v_row from "better_supabase"."eval_runs" x where x."id" = finish_eval_run.run;
    if not found then
      raise exception 'No eval run %', finish_eval_run.run using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'organization_id', v_row."workspace_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$$;
revoke execute on function "better_supabase"."finish_eval_run"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_eval_run"(uuid, text) to service_role;

create or replace function "better_supabase"."get_eval_run"(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  select x.* into v_row from "better_supabase"."eval_runs" x where x."id" = get_eval_run.run;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'organization_id', v_row."workspace_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$$;
revoke execute on function "better_supabase"."get_eval_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."get_eval_run"(uuid) to service_role;

-- The runs of a dataset, newest first.
create or replace function "better_supabase"."list_eval_runs"(dataset uuid, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', p."id", 'dataset_id', p."dataset_id", 'organization_id', p."workspace_id", 'prompt_name', p."prompt_name", 'prompt_version', p."prompt_version", 'model', p."model", 'scorers', p."scorers", 'status', p."status", 'summary', p."summary", 'created_at', p."created_at", 'finished_at', p."finished_at") order by p."created_at" desc), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."eval_runs" x where x."dataset_id" = list_eval_runs.dataset
      order by x."created_at" desc limit least(greatest(coalesce(list_eval_runs.max_rows, 100), 1), 1000)
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."list_eval_runs"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_eval_runs"(uuid, integer) to service_role;

-- The results of a run in item order after the given item, optionally only
-- the ones that did not pass.
create or replace function "better_supabase"."list_eval_results"(run uuid, only_failed boolean default false, after uuid default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('run_id', p."run_id", 'item_id', p."item_id", 'output', p."output", 'scores', p."scores", 'passed', p."passed", 'error', p."error", 'latency_ms', p."latency_ms", 'created_at', p."created_at") order by p."item_id"), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."eval_results" x
      where x."run_id" = list_eval_results.run
        and (not coalesce(list_eval_results.only_failed, false) or not x."passed")
        and (list_eval_results.after is null or x."item_id" > list_eval_results.after)
      order by x."item_id" limit least(greatest(coalesce(list_eval_results.max_rows, 100), 1), 1000)
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."list_eval_results"(uuid, boolean, uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."list_eval_results"(uuid, boolean, uuid, integer) to service_role;

-- Compares two runs of the same dataset. An item regressed when the base run
-- passed it and the candidate did not, or, with score_drop, when its average
-- score fell by more than that. It improved on the reverse. Items only one run
-- has a result for count as missing.
create or replace function "better_supabase"."compare_eval_runs"(base uuid, candidate uuid, score_drop numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_base "better_supabase"."eval_runs"%rowtype;
  v_candidate "better_supabase"."eval_runs"%rowtype;
  v_base_summary jsonb;
  v_candidate_summary jsonb;
begin
  select x.* into v_base from "better_supabase"."eval_runs" x where x."id" = compare_eval_runs.base;
  if not found then
    raise exception 'No eval run %', compare_eval_runs.base using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
  end if;
  select x.* into v_candidate from "better_supabase"."eval_runs" x where x."id" = compare_eval_runs.candidate;
  if not found then
    raise exception 'No eval run %', compare_eval_runs.candidate using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
  end if;
  if v_base."dataset_id" <> v_candidate."dataset_id" then
    raise exception 'Runs belong to different datasets' using errcode = '22023', hint = 'EVAL_RUN_MISMATCH';
  end if;
  v_base_summary := "better_supabase"."eval_run_summary"(compare_eval_runs.base);
  v_candidate_summary := "better_supabase"."eval_run_summary"(compare_eval_runs.candidate);
  return (
    with joined as materialized (
      select coalesce(b."item_id", c."item_id") as item,
        b."passed" as base_passed, c."passed" as candidate_passed,
        (select avg((e.value ->> 'score')::numeric) from jsonb_each(b."scores") e) as base_score, (select avg((e.value ->> 'score')::numeric) from jsonb_each(c."scores") e) as candidate_score,
        b."output" as base_output, c."output" as candidate_output
      from (select * from "better_supabase"."eval_results" where "run_id" = compare_eval_runs.base) b
      full join (select * from "better_supabase"."eval_results" where "run_id" = compare_eval_runs.candidate) c on c."item_id" = b."item_id"
    ), tagged as (
      select j.*, case
        when j.base_passed is null or j.candidate_passed is null then 'missing'
        when j.base_passed and not j.candidate_passed then 'regression'
        when not j.base_passed and j.candidate_passed then 'improvement'
        when compare_eval_runs.score_drop is not null and j.base_score - j.candidate_score > compare_eval_runs.score_drop then 'regression'
        when compare_eval_runs.score_drop is not null and j.candidate_score - j.base_score > compare_eval_runs.score_drop then 'improvement'
        else 'unchanged' end as kind
      from joined j
    )
    select jsonb_build_object(
      'base', v_base_summary,
      'candidate', v_candidate_summary,
      'pass_rate_delta', round(coalesce((v_candidate_summary ->> 'passRate')::numeric, 0) - coalesce((v_base_summary ->> 'passRate')::numeric, 0), 4),
      'regressions', coalesce(jsonb_agg(jsonb_build_object('item_id', t.item, 'base_score', t.base_score, 'candidate_score', t.candidate_score, 'base_output', t.base_output, 'candidate_output', t.candidate_output) order by t.item) filter (where t.kind = 'regression'), '[]'::jsonb),
      'improvements', coalesce(jsonb_agg(jsonb_build_object('item_id', t.item, 'base_score', t.base_score, 'candidate_score', t.candidate_score) order by t.item) filter (where t.kind = 'improvement'), '[]'::jsonb),
      'unchanged', count(*) filter (where t.kind = 'unchanged'),
      'missing', count(*) filter (where t.kind = 'missing')
    )
    from tagged t
  );
end;
$$;
revoke execute on function "better_supabase"."compare_eval_runs"(uuid, uuid, numeric) from public, anon, authenticated;
grant execute on function "better_supabase"."compare_eval_runs"(uuid, uuid, numeric) to service_role;

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

-- ==== data supabase/better-supabase-data/900_better_supabase_171_ai_evals.sql
-- better-supabase module: ai-evals
-- @bsb-block-data ai-evals
-- @bsb-hash sha256:29804813de8ce89a753953e7c33b5e6ba8a2a96b56aa5d12ccea830e60103d08
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-evals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
