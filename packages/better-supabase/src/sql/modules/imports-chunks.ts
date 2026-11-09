import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { ensureCheck, fail, lockTable, serviceGrant } from "../shared.ts";

/** `names.tables.chunks`: the stored items of one chunk of an entity's import. */
export const CHUNK_TABLE = {
  name: "import_chunks",
  app: {},
  lifecycle: { tenant: "tenant", export: false },
  columns: {
    run: "run_id",
    tenant: "tenant_id",
    entity: "entity",
    chunk: "chunk",
    items: "items",
    status: "status",
    result: "result",
    claimedAt: "claimed_at",
    doneAt: "done_at",
    createdAt: "created_at",
  },
} as const;

/**
 * The chunk table: one row per chunk of an entity's items, so a worker writes a
 * large import in batches that each survive a retry (ADR 0437).
 */
export function chunkTable(ctx: BlockSqlContext, runs: string): string {
  const k = ctx.tableName("chunks").name;
  const chunks = ctx.table("chunks");
  const c = (column: string): string => ctx.col("chunks", column);

  return `
create table if not exists ${chunks} (
  ${c("run")} uuid not null references ${runs} (${ctx.col("runs", "id")}) on delete cascade,
  ${c("tenant")} ${ctx.idType} not null,
  ${c("entity")} text not null,
  ${c("chunk")} integer not null,
  ${c("items")} jsonb not null,
  ${c("status")} text not null default 'pending',
  ${c("result")} jsonb,
  ${c("claimedAt")} timestamptz,
  ${c("doneAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now(),
  primary key (${c("run")}, ${c("entity")}, ${c("chunk")})
);
${ensureCheck(chunks, `bsb_${k}_status`, `${c("status")} in ('pending', 'claimed', 'done')`)}
${lockTable(chunks, { read: false })}
create index if not exists ${sqlIdent(`${k}_tenant_idx`)} on ${chunks} (${c("tenant")});
`;
}

/**
 * `store_import_chunk`, `claim_import_chunk`, `complete_import_chunk`,
 * `process_import_chunk` and `import_chunk_progress`, all for the service
 * role.
 */
export function chunkFunctions(ctx: BlockSqlContext, runs: string): string {
  const chunks = ctx.table("chunks");
  const c = (column: string): string => ctx.col("chunks", column);
  const r = (column: string): string => ctx.col("runs", column);
  const fn = (name: string): string => ctx.fn(name);

  return `
-- Stores the items of one chunk of an entity, ready for a worker. Storing a chunk
-- again before it is done replaces its items; a done chunk is left as it is and
-- the answer is false.
create or replace function ${fn("store_import_chunk")}(run uuid, entity text, chunk integer, items jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs};
begin
  select * into v_run from ${runs} r where r.${r("id")} = store_import_chunk.run;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    ${fail("IMPORT_ITEM_INVALID", "a chunk has a number from 0 and an array of items", "22023")}
  end if;
  insert into ${chunks} (${c("run")}, ${c("tenant")}, ${c("entity")}, ${c("chunk")}, ${c("items")})
  values (store_import_chunk.run, v_run.${r("tenant")}, store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict (${c("run")}, ${c("entity")}, ${c("chunk")}) do update
    set ${c("items")} = excluded.${c("items")}, ${c("status")} = 'pending', ${c("claimedAt")} = null
    where ${chunks}.${c("status")} <> 'done';
  return found;
end;
$$;
${serviceGrant(`${fn("store_import_chunk")}(uuid, text, integer, jsonb)`)}

-- Takes a pending chunk, or one whose claim is older than lease seconds (a worker
-- that died), and returns { entity, chunk, items }. Null when the chunk is done,
-- missing or held by a live worker. Rows another worker holds are skipped, not waited for.
create or replace function ${fn("claim_import_chunk")}(run uuid, entity text, chunk integer, lease integer default 300)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_items jsonb;
begin
  with pick as (
    select x.${c("run")}, x.${c("entity")}, x.${c("chunk")}
    from ${chunks} x
    where x.${c("run")} = claim_import_chunk.run and x.${c("entity")} = claim_import_chunk.entity and x.${c("chunk")} = claim_import_chunk.chunk
      and (x.${c("status")} = 'pending' or (x.${c("status")} = 'claimed' and x.${c("claimedAt")} < now() - make_interval(secs => greatest(claim_import_chunk.lease, 1))))
    for update skip locked
  )
  update ${chunks} x set ${c("status")} = 'claimed', ${c("claimedAt")} = now()
  from pick
  where x.${c("run")} = pick.${c("run")} and x.${c("entity")} = pick.${c("entity")} and x.${c("chunk")} = pick.${c("chunk")}
  returning x.${c("items")} into v_items;
  if v_items is null then
    return null;
  end if;
  return jsonb_build_object('entity', claim_import_chunk.entity, 'chunk', claim_import_chunk.chunk, 'items', v_items);
end;
$$;
${serviceGrant(`${fn("claim_import_chunk")}(uuid, text, integer, integer)`)}

-- Marks a claimed chunk done and keeps what its batch answered.
create or replace function ${fn("complete_import_chunk")}(run uuid, entity text, chunk integer, result jsonb)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  update ${chunks} x set ${c("status")} = 'done', ${c("doneAt")} = now(), ${c("result")} = complete_import_chunk.result
  where x.${c("run")} = complete_import_chunk.run and x.${c("entity")} = complete_import_chunk.entity
    and x.${c("chunk")} = complete_import_chunk.chunk and x.${c("status")} = 'claimed';
  return found;
end;
$$;
${serviceGrant(`${fn("complete_import_chunk")}(uuid, text, integer, jsonb)`)}

-- One worker step: claim the chunk, write it with import_upsert_batch and mark it
-- done, in one transaction, so a failure leaves the chunk pending for the next try.
-- A chunk that is done answers what its batch answered; one that is missing or
-- held by another worker answers { skipped: true }.
create or replace function ${fn("process_import_chunk")}(run uuid, entity text, chunk integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x.${c("result")} into v_done from ${chunks} x
  where x.${c("run")} = process_import_chunk.run and x.${c("entity")} = process_import_chunk.entity
    and x.${c("chunk")} = process_import_chunk.chunk and x.${c("status")} = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  v_claim := ${fn("claim_import_chunk")}(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := ${fn("import_upsert_batch")}(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform ${fn("complete_import_chunk")}(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$$;
${serviceGrant(`${fn("process_import_chunk")}(uuid, text, integer)`)}

-- How many chunks of a run are pending, claimed and done, so a caller knows when to
-- finish the run.
create or replace function ${fn("import_chunk_progress")}(run uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'pending', count(*) filter (where x.${c("status")} = 'pending'),
    'claimed', count(*) filter (where x.${c("status")} = 'claimed'),
    'done', count(*) filter (where x.${c("status")} = 'done')
  )
  from ${chunks} x
  where x.${c("run")} = import_chunk_progress.run
$$;
${serviceGrant(`${fn("import_chunk_progress")}(uuid)`)}
`;
}

/** The contract entries of the chunk functions. */
export const CHUNK_CONTRACT = [
  {
    name: "store_import_chunk",
    args: ["uuid", "text", "integer", "jsonb"],
    returns: "boolean",
  },
  {
    name: "claim_import_chunk",
    args: ["uuid", "text", "integer", "integer"],
    returns: "jsonb",
  },
  {
    name: "complete_import_chunk",
    args: ["uuid", "text", "integer", "jsonb"],
    returns: "boolean",
  },
  {
    name: "process_import_chunk",
    args: ["uuid", "text", "integer"],
    returns: "jsonb",
  },
  { name: "import_chunk_progress", args: ["uuid"], returns: "jsonb" },
] as const;
