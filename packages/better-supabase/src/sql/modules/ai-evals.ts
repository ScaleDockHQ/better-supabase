import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, raise, schemaPreamble, serviceGrant } from "../shared.ts";

const DATASETS = {
  id: "id",
  tenant: "organization_id",
  name: "name",
  description: "description",
  createdAt: "created_at",
} as const;

const ITEMS = {
  id: "id",
  dataset: "dataset_id",
  input: "input",
  expected: "expected",
  metadata: "metadata",
  sourceChat: "source_chat_id",
  sourceMessage: "source_message_id",
  createdAt: "created_at",
} as const;

const RUNS = {
  id: "id",
  dataset: "dataset_id",
  tenant: "organization_id",
  promptName: "prompt_name",
  promptVersion: "prompt_version",
  model: "model",
  scorers: "scorers",
  status: "status",
  summary: "summary",
  createdAt: "created_at",
  finishedAt: "finished_at",
} as const;

const RESULTS = {
  run: "run_id",
  item: "item_id",
  output: "output",
  scores: "scores",
  passed: "passed",
  error: "error",
  latencyMs: "latency_ms",
  createdAt: "created_at",
} as const;

const NAMES: BlockSqlNames = {
  options: ["maxItems"],
  tables: {
    datasets: {
      name: "eval_datasets",
      columns: DATASETS,
      lifecycle: { tenant: "tenant" },
      app: {},
    },
    items: { name: "eval_items", columns: ITEMS, app: {} },
    runs: {
      name: "eval_runs",
      columns: RUNS,
      lifecycle: { tenant: "tenant" },
      app: {},
    },
    results: { name: "eval_results", columns: RESULTS, app: {} },
  },
};

/** The message text of a `parts` column, joined from its text parts. */
const textOf = (parts: string): string =>
  `(select string_agg(p.value ->> 'text', '' order by p.ordinality) from jsonb_array_elements(case when jsonb_typeof(${parts}) = 'array' then ${parts} else '[]'::jsonb end) with ordinality as p(value, ordinality) where p.value ->> 'type' = 'text')`;

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const d = (column: keyof typeof DATASETS): string =>
    ctx.col("datasets", column);

  const i = (column: keyof typeof ITEMS): string => ctx.col("items", column);
  const r = (column: keyof typeof RUNS): string => ctx.col("runs", column);

  const s = (column: keyof typeof RESULTS): string =>
    ctx.col("results", column);

  const datasets = ctx.table("datasets");
  const items = ctx.table("items");
  const runs = ctx.table("runs");
  const results = ctx.table("results");
  const datasetsName = ctx.tableName("datasets").name;
  const itemsName = ctx.tableName("items").name;
  const runsName = ctx.tableName("runs").name;
  const maxItems = ctx.number("maxItems", 5000);

  if (!Number.isInteger(maxItems) || maxItems < 1) {
    throw new TypeError(
      "blocks.ai-evals.options.maxItems must be a whole number of items",
    );
  }

  const datasetJson = (alias: string): string =>
    `jsonb_build_object(${Object.entries(DATASETS)
      .map(
        ([key, column]) =>
          // SAFETY: keys come from Object.entries of the same column map.
          `'${column}', ${alias}.${d(key as keyof typeof DATASETS)}`,
      )
      .join(", ")})`;

  const itemJson = (alias: string): string =>
    `jsonb_build_object(${Object.entries(ITEMS)
      .map(
        ([key, column]) =>
          // SAFETY: keys come from Object.entries of the same column map.
          `'${column}', ${alias}.${i(key as keyof typeof ITEMS)}`,
      )
      .join(", ")})`;

  const runJson = (alias: string): string =>
    `jsonb_build_object(${Object.entries(RUNS)
      .map(
        ([key, column]) =>
          // SAFETY: keys come from Object.entries of the same column map.
          `'${column}', ${alias}.${r(key as keyof typeof RUNS)}`,
      )
      .join(", ")})`;

  const resultJson = (alias: string): string =>
    `jsonb_build_object(${Object.entries(RESULTS)
      .map(
        ([key, column]) =>
          // SAFETY: keys come from Object.entries of the same column map.
          `'${column}', ${alias}.${s(key as keyof typeof RESULTS)}`,
      )
      .join(", ")})`;

  const limit = (value: string): string =>
    `least(greatest(coalesce(${value}, 100), 1), 1000)`;

  const itemScore = (scores: string): string =>
    `(select avg((e.value ->> 'score')::numeric) from jsonb_each(${scores}) e)`;

  const missing = (what: string, code: string, args: string): string =>
    raise(`No ${what} %`, "P0002", code, args);

  let feedback = "";

  if (ctx.installed("ai-chat")) {
    const chat = ctx.of("ai-chat");
    const f = (column: string): string => chat.col("feedback", column);
    const m = (column: string): string => chat.col("messages", column);
    const c = (column: string): string => chat.col("chats", column);
    const hasComment = chat.has("feedback", "comment");
    const hasReason = chat.has("feedback", "reason");

    const stamp = chat.has("feedback", "updatedAt")
      ? f("updatedAt")
      : chat.has("feedback", "createdAt")
        ? f("createdAt")
        : undefined;

    feedback = `
-- Copies rated ai-chat replies into a dataset: the user message before the
-- reply is the input, the rating, reason and comment go to the metadata, and a
-- thumbs up keeps the reply as the expected output. A reply that is already in
-- the dataset is skipped. A tenant's dataset only takes that tenant's chats.
create or replace function ${fn("add_eval_items_from_feedback")}(dataset uuid, rating integer default -1, since timestamptz default null, max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dataset ${datasets}%rowtype;
  v_count integer;
begin
  select x.* into v_dataset from ${datasets} x where x.${d("id")} = add_eval_items_from_feedback.dataset;
  if not found then
    ${missing("eval dataset", "EVAL_DATASET_NOT_FOUND", "add_eval_items_from_feedback.dataset")}
  end if;
  if add_eval_items_from_feedback.rating not in (-1, 1) then
    ${raise("rating must be 1 or -1", "22023", "EVAL_INVALID")}
  end if;
  with picked as materialized (
    select fb.${f("chat")} as chat_id, fb.${f("message")}::text as message_id,
      ${textOf("q.parts")} as prompt,
      ${textOf("a.parts")} as reply,
      ${hasReason ? `fb.${f("reason")}` : "null::text"} as reason,
      ${hasComment ? `fb.${f("comment")}` : "null::text"} as comment
    from ${chat.table("feedback")} fb
    join ${chat.table("messages")} a on a.${m("chat")} = fb.${f("chat")} and a.${m("id")} = fb.${f("message")}
    join ${chat.table("messages")} q on q.${m("chat")} = a.${m("chat")} and q.${m("id")} = a.${m("parent")}
    join ${chat.table("chats")} ch on ch.${c("id")} = fb.${f("chat")}
    where fb.${f("rating")} = add_eval_items_from_feedback.rating
      and (v_dataset.${d("tenant")} is null or ch.${c("tenant")} = v_dataset.${d("tenant")})${stamp === undefined ? "" : `\n      and (add_eval_items_from_feedback.since is null or fb.${stamp} >= add_eval_items_from_feedback.since)`}
    order by ${stamp === undefined ? `fb.${f("chat")}` : `fb.${stamp} desc`}
    limit ${limit("add_eval_items_from_feedback.max_rows")}
  ), added as (
    insert into ${items} (${i("dataset")}, ${i("input")}, ${i("expected")}, ${i("metadata")}, ${i("sourceChat")}, ${i("sourceMessage")})
    select v_dataset.${d("id")}, jsonb_build_object('prompt', p.prompt),
      case when add_eval_items_from_feedback.rating = 1 then jsonb_build_object('output', p.reply) end,
      jsonb_build_object('source', 'ai-chat-feedback', 'rating', add_eval_items_from_feedback.rating, 'reason', p.reason, 'comment', p.comment, 'reply', p.reply),
      p.chat_id::text, p.message_id
    from picked p
    where p.prompt is not null
    on conflict do nothing
    returning 1
  )
  select count(*) into v_count from added;
  return v_count;
end;
$$;
${serviceGrant(`${fn("add_eval_items_from_feedback")}(uuid, integer, timestamptz, integer)`)}`;
  } else {
    feedback = `
-- Needs the ai-chat block, which is not installed here.
create or replace function ${fn("add_eval_items_from_feedback")}(dataset uuid, rating integer default -1, since timestamptz default null, max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${raise("add_eval_items_from_feedback needs the ai-chat block", "55000", "EVAL_FEEDBACK_UNAVAILABLE")}
end;
$$;
${serviceGrant(`${fn("add_eval_items_from_feedback")}(uuid, integer, timestamptz, integer)`)}`;
  }

  return `${schemaPreamble(ctx)}
-- Evaluation datasets and runs. A dataset holds items (an input and, when
-- known, the expected output); a run replays the items against one prompt
-- version and model and keeps a score per scorer for each item. Inputs and
-- outputs can hold user content, so only the service role reads and writes
-- them.
create table if not exists ${datasets} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${id},
  ${d("name")} text not null check (${d("name")} ~ '^[a-z0-9][a-z0-9_.:/-]{0,127}$'),
  ${d("description")} text check (length(${d("description")}) <= 2000),
  ${d("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${sqlIdent(`bsb_${datasetsName}_key`)} on ${datasets} ((coalesce(${d("tenant")}::text, '')), ${d("name")});
${lockTable(datasets)}

create table if not exists ${items} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("dataset")} uuid not null references ${datasets} (${d("id")}) on delete cascade,
  ${i("input")} jsonb not null,
  ${i("expected")} jsonb,
  ${i("metadata")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${i("metadata")}) = 'object'),
  ${i("sourceChat")} text,
  ${i("sourceMessage")} text,
  ${i("createdAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${itemsName}_dataset_idx`)} on ${items} (${i("dataset")}, ${i("id")});
create unique index if not exists ${sqlIdent(`bsb_${itemsName}_source_key`)} on ${items} (${i("dataset")}, ${i("sourceChat")}, ${i("sourceMessage")}) where ${i("sourceChat")} is not null;
${lockTable(items)}

create table if not exists ${runs} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("dataset")} uuid not null references ${datasets} (${d("id")}) on delete cascade,
  ${r("tenant")} ${id},
  ${r("promptName")} text not null,
  ${r("promptVersion")} integer not null check (${r("promptVersion")} >= 1),
  ${r("model")} text not null,
  ${r("scorers")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${r("scorers")}) = 'array'),
  ${r("status")} text not null default 'running' check (${r("status")} in ('running', 'completed', 'failed', 'cancelled')),
  ${r("summary")} jsonb,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("finishedAt")} timestamptz
);
create index if not exists ${sqlIdent(`${runsName}_dataset_idx`)} on ${runs} (${r("dataset")}, ${r("createdAt")} desc);
${lockTable(runs)}

create table if not exists ${results} (
  ${s("run")} uuid not null references ${runs} (${r("id")}) on delete cascade,
  ${s("item")} uuid not null references ${items} (${i("id")}) on delete cascade,
  ${s("output")} text,
  ${s("scores")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${s("scores")}) = 'object'),
  ${s("passed")} boolean not null,
  ${s("error")} text,
  ${s("latencyMs")} integer check (${s("latencyMs")} >= 0),
  ${s("createdAt")} timestamptz not null default now(),
  primary key (${s("run")}, ${s("item")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("results").name}_item_idx`)} on ${results} (${s("item")});
${lockTable(results)}

-- Creates a dataset, or returns the one with that name for the tenant.
create or replace function ${fn("create_eval_dataset")}(name text, tenant ${id} default null, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${datasets}%rowtype;
begin
  insert into ${datasets} (${d("tenant")}, ${d("name")}, ${d("description")})
  values (create_eval_dataset.tenant, create_eval_dataset.name, create_eval_dataset.description)
  on conflict ((coalesce(${d("tenant")}::text, '')), ${d("name")}) do update set
    ${d("description")} = coalesce(excluded.${d("description")}, ${datasets}.${d("description")})
  returning * into v_row;
  return ${datasetJson("v_row")};
end;
$$;
${serviceGrant(`${fn("create_eval_dataset")}(text, ${id}, text)`)}

-- Adds items, each an object with input and optionally expected and
-- metadata. Returns the number added; a dataset holds at most ${maxItems}.
create or replace function ${fn("add_eval_items")}(dataset uuid, items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  if not exists (select 1 from ${datasets} x where x.${d("id")} = add_eval_items.dataset) then
    ${missing("eval dataset", "EVAL_DATASET_NOT_FOUND", "add_eval_items.dataset")}
  end if;
  if jsonb_typeof(add_eval_items.items) is distinct from 'array' then
    ${raise("items must be a JSON array", "22023", "EVAL_INVALID")}
  end if;
  if exists (select 1 from jsonb_array_elements(add_eval_items.items) e where jsonb_typeof(e.value) <> 'object' or not (e.value ? 'input')) then
    ${raise("every item needs an input", "22023", "EVAL_INVALID")}
  end if;
  if (select count(*) from ${items} x where x.${i("dataset")} = add_eval_items.dataset) + jsonb_array_length(add_eval_items.items) > ${maxItems} then
    ${raise(`A dataset holds at most ${maxItems} items`, "54000", "EVAL_DATASET_FULL")}
  end if;
  insert into ${items} (${i("dataset")}, ${i("input")}, ${i("expected")}, ${i("metadata")})
  select add_eval_items.dataset, e.value -> 'input', e.value -> 'expected', coalesce(e.value -> 'metadata', '{}'::jsonb)
  from jsonb_array_elements(add_eval_items.items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("add_eval_items")}(uuid, jsonb)`)}
${feedback}

-- The items of a dataset in id order after the given id. With pending_run,
-- only the items that run has no result for yet, so a job can resume.
create or replace function ${fn("list_eval_items")}(dataset uuid, pending_run uuid default null, after uuid default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(${itemJson("p")} order by p.${i("id")}), '[]'::jsonb)
    from (
      select x.* from ${items} x
      where x.${i("dataset")} = list_eval_items.dataset
        and (list_eval_items.after is null or x.${i("id")} > list_eval_items.after)
        and (list_eval_items.pending_run is null or not exists (
          select 1 from ${results} y where y.${s("run")} = list_eval_items.pending_run and y.${s("item")} = x.${i("id")}
        ))
      order by x.${i("id")}
      limit ${limit("list_eval_items.max_rows")}
    ) p
  );
end;
$$;
${serviceGrant(`${fn("list_eval_items")}(uuid, uuid, uuid, integer)`)}

-- Starts a run of a dataset against one prompt version and model. scorers
-- describes the scorers the run uses (name and kind) and is kept with it.
create or replace function ${fn("create_eval_run")}(dataset uuid, prompt_name text, prompt_version integer, model text, scorers jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dataset ${datasets}%rowtype;
  v_row ${runs}%rowtype;
begin
  select x.* into v_dataset from ${datasets} x where x.${d("id")} = create_eval_run.dataset;
  if not found then
    ${missing("eval dataset", "EVAL_DATASET_NOT_FOUND", "create_eval_run.dataset")}
  end if;
  insert into ${runs} (${r("dataset")}, ${r("tenant")}, ${r("promptName")}, ${r("promptVersion")}, ${r("model")}, ${r("scorers")})
  values (create_eval_run.dataset, v_dataset.${d("tenant")}, create_eval_run.prompt_name, create_eval_run.prompt_version, create_eval_run.model, coalesce(create_eval_run.scorers, '[]'::jsonb))
  returning * into v_row;
  return ${runJson("v_row")};
end;
$$;
${serviceGrant(`${fn("create_eval_run")}(uuid, text, integer, text, jsonb)`)}

-- Stores the output and scores of one item in a running run, replacing an
-- earlier result so a retried job is safe. scores maps a scorer name to
-- { score, passed, reason }; the result passes when there is no error and
-- every scorer passed.
create or replace function ${fn("record_eval_result")}(run uuid, item uuid, output text default null, scores jsonb default '{}'::jsonb, error text default null, latency_ms integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs}%rowtype;
  v_row ${results}%rowtype;
  v_scores jsonb := coalesce(record_eval_result.scores, '{}'::jsonb);
begin
  select x.* into v_run from ${runs} x where x.${r("id")} = record_eval_result.run;
  if not found then
    ${missing("eval run", "EVAL_RUN_NOT_FOUND", "record_eval_result.run")}
  end if;
  if v_run.${r("status")} <> 'running' then
    ${raise("Eval run % is closed", "55000", "EVAL_RUN_CLOSED", "record_eval_result.run")}
  end if;
  if not exists (select 1 from ${items} x where x.${i("id")} = record_eval_result.item and x.${i("dataset")} = v_run.${r("dataset")}) then
    ${missing("eval item", "EVAL_ITEM_NOT_FOUND", "record_eval_result.item")}
  end if;
  if jsonb_typeof(v_scores) <> 'object' then
    ${raise("scores must be a JSON object", "22023", "EVAL_INVALID")}
  end if;
  insert into ${results} (${s("run")}, ${s("item")}, ${s("output")}, ${s("scores")}, ${s("passed")}, ${s("error")}, ${s("latencyMs")})
  values (record_eval_result.run, record_eval_result.item, record_eval_result.output, v_scores,
    record_eval_result.error is null and not exists (select 1 from jsonb_each(v_scores) e where (e.value ->> 'passed') is distinct from 'true'),
    record_eval_result.error, record_eval_result.latency_ms)
  on conflict (${s("run")}, ${s("item")}) do update set
    ${s("output")} = excluded.${s("output")}, ${s("scores")} = excluded.${s("scores")}, ${s("passed")} = excluded.${s("passed")},
    ${s("error")} = excluded.${s("error")}, ${s("latencyMs")} = excluded.${s("latencyMs")}, ${s("createdAt")} = now()
  returning * into v_row;
  return ${resultJson("v_row")};
end;
$$;
${serviceGrant(`${fn("record_eval_result")}(uuid, uuid, text, jsonb, text, integer)`)}

-- The totals of a run: results, passed, failed, errored, the pass rate and the
-- average score and pass rate per scorer.
create or replace function ${fn("eval_run_summary")}(run uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'total', count(*),
    'passed', count(*) filter (where x.${s("passed")}),
    'failed', count(*) filter (where not x.${s("passed")} and x.${s("error")} is null),
    'errored', count(*) filter (where x.${s("error")} is not null),
    'passRate', coalesce(round(avg(case when x.${s("passed")} then 1 else 0 end), 4), 0),
    'scorers', coalesce((
      select jsonb_object_agg(t.name, jsonb_build_object('avg', t.mean, 'passRate', t.rate))
      from (
        select e.key as name, round(avg((e.value ->> 'score')::numeric), 4) as mean,
          round(avg(case when (e.value ->> 'passed') = 'true' then 1 else 0 end), 4) as rate
        from ${results} y, jsonb_each(y.${s("scores")}) e
        where y.${s("run")} = eval_run_summary.run
        group by e.key
      ) t
    ), '{}'::jsonb)
  )
  from ${results} x where x.${s("run")} = eval_run_summary.run;
$$;
${serviceGrant(`${fn("eval_run_summary")}(uuid)`)}

-- Closes a running run (completed, failed or cancelled) and stores its summary.
create or replace function ${fn("finish_eval_run")}(run uuid, status text default 'completed')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${runs}%rowtype;
begin
  if finish_eval_run.status not in ('completed', 'failed', 'cancelled') then
    ${raise("status must be completed, failed or cancelled", "22023", "EVAL_INVALID")}
  end if;
  update ${runs} x set ${r("status")} = finish_eval_run.status, ${r("summary")} = ${fn("eval_run_summary")}(finish_eval_run.run), ${r("finishedAt")} = now()
  where x.${r("id")} = finish_eval_run.run and x.${r("status")} = 'running'
  returning * into v_row;
  if not found then
    select x.* into v_row from ${runs} x where x.${r("id")} = finish_eval_run.run;
    if not found then
      ${missing("eval run", "EVAL_RUN_NOT_FOUND", "finish_eval_run.run")}
    end if;
  end if;
  return ${runJson("v_row")};
end;
$$;
${serviceGrant(`${fn("finish_eval_run")}(uuid, text)`)}

create or replace function ${fn("get_eval_run")}(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${runs}%rowtype;
begin
  select x.* into v_row from ${runs} x where x.${r("id")} = get_eval_run.run;
  if not found then
    return null;
  end if;
  return ${runJson("v_row")};
end;
$$;
${serviceGrant(`${fn("get_eval_run")}(uuid)`)}

-- The runs of a dataset, newest first.
create or replace function ${fn("list_eval_runs")}(dataset uuid, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(${runJson("p")} order by p.${r("createdAt")} desc), '[]'::jsonb)
    from (
      select x.* from ${runs} x where x.${r("dataset")} = list_eval_runs.dataset
      order by x.${r("createdAt")} desc limit ${limit("list_eval_runs.max_rows")}
    ) p
  );
end;
$$;
${serviceGrant(`${fn("list_eval_runs")}(uuid, integer)`)}

-- The results of a run in item order after the given item, optionally only
-- the ones that did not pass.
create or replace function ${fn("list_eval_results")}(run uuid, only_failed boolean default false, after uuid default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(${resultJson("p")} order by p.${s("item")}), '[]'::jsonb)
    from (
      select x.* from ${results} x
      where x.${s("run")} = list_eval_results.run
        and (not coalesce(list_eval_results.only_failed, false) or not x.${s("passed")})
        and (list_eval_results.after is null or x.${s("item")} > list_eval_results.after)
      order by x.${s("item")} limit ${limit("list_eval_results.max_rows")}
    ) p
  );
end;
$$;
${serviceGrant(`${fn("list_eval_results")}(uuid, boolean, uuid, integer)`)}

-- Compares two runs of the same dataset. An item regressed when the base run
-- passed it and the candidate did not, or, with score_drop, when its average
-- score fell by more than that. It improved on the reverse. Items only one run
-- has a result for count as missing.
create or replace function ${fn("compare_eval_runs")}(base uuid, candidate uuid, score_drop numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_base ${runs}%rowtype;
  v_candidate ${runs}%rowtype;
  v_base_summary jsonb;
  v_candidate_summary jsonb;
begin
  select x.* into v_base from ${runs} x where x.${r("id")} = compare_eval_runs.base;
  if not found then
    ${missing("eval run", "EVAL_RUN_NOT_FOUND", "compare_eval_runs.base")}
  end if;
  select x.* into v_candidate from ${runs} x where x.${r("id")} = compare_eval_runs.candidate;
  if not found then
    ${missing("eval run", "EVAL_RUN_NOT_FOUND", "compare_eval_runs.candidate")}
  end if;
  if v_base.${r("dataset")} <> v_candidate.${r("dataset")} then
    ${raise("Runs belong to different datasets", "22023", "EVAL_RUN_MISMATCH")}
  end if;
  v_base_summary := ${fn("eval_run_summary")}(compare_eval_runs.base);
  v_candidate_summary := ${fn("eval_run_summary")}(compare_eval_runs.candidate);
  return (
    with joined as materialized (
      select coalesce(b.${s("item")}, c.${s("item")}) as item,
        b.${s("passed")} as base_passed, c.${s("passed")} as candidate_passed,
        ${itemScore(`b.${s("scores")}`)} as base_score, ${itemScore(`c.${s("scores")}`)} as candidate_score,
        b.${s("output")} as base_output, c.${s("output")} as candidate_output
      from (select * from ${results} where ${s("run")} = compare_eval_runs.base) b
      full join (select * from ${results} where ${s("run")} = compare_eval_runs.candidate) c on c.${s("item")} = b.${s("item")}
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
${serviceGrant(`${fn("compare_eval_runs")}(uuid, uuid, numeric)`)}`;
}

export const AI_EVALS: BlockSqlDefinition = {
  name: "ai-evals",
  title: "AI evals",
  description:
    "Evaluation datasets of inputs and expected outputs (imported or taken from rated ai-chat replies), runs against a prompt version and model, a score per scorer and item, and a regression compare between two runs; only the service role reads and writes them.",
  requires: [],
  integrates: ["ai-chat"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
