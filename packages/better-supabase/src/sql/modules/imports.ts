import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { importWaves } from "../../blocks/imports/waves.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { filterAny, listBody, listDeclare } from "../list-template.ts";
import {
  ensureCheck,
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  sha256HexSql,
  userGrant,
} from "../shared.ts";
import { batchSql } from "./imports-batch.ts";
import { chunkFunctions, chunkTable } from "./imports-chunks.ts";
import { importContract as contract } from "./imports-contract.ts";
import { hashFunctions } from "./imports-hashes.ts";
import { eventsPolicyOf, importIntegritySql } from "./imports-integrity.ts";
import {
  importIssueCounts,
  importIssueHelpers,
  importIssuesTable,
} from "./imports-issues.ts";
import { importLifecycleSql, rebaseImportSql } from "./imports-lifecycle.ts";
import { IMPORT_NAMES } from "./imports-names.ts";
import { importSourcesSql } from "./imports-sources.ts";
import {
  assignCase,
  naturalLookupOf,
  readerCaseOf,
  refResolveSql,
  targetsOf,
} from "./imports-targets.ts";
import { OPERATIONS } from "./permissions-model.ts";

const DRY_RUN_STATE = "BSDRY";

function auditModeOf(ctx: BlockSqlContext): "rows" | "summary" {
  const raw: unknown = ctx.option("audit") ?? "rows";

  if (raw !== "rows" && raw !== "summary") {
    throw new TypeError(
      "blocks['imports'].options.audit must be rows or summary",
    );
  }

  return raw;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const runs = ctx.table("runs");
  const records = ctx.table("records");
  const r = (column: string): string => ctx.col("runs", column);
  const x = (column: string): string => ctx.col("records", column);
  const manage = ctx.permission("manage", OPERATIONS["imports.manage"]);
  const targets = targetsOf(ctx);

  // A dependency cycle fails here, before any SQL is written.
  importWaves(targets);
  const eventsPolicy = sqlString(eventsPolicyOf(ctx));
  const auditMode = auditModeOf(ctx);
  const searchDeferral = ctx.installed("search");

  // The run's records are indexed once, when it closes (ADR 0844).
  const refreshRun = (run: string): string =>
    searchDeferral
      ? `  perform ${ctx.of("search").fn("search_refresh_run")}(${run});\n`
      : "";

  const refs = `${ctx.schema}.${ctx.tableName("refs").name}`;
  const ref = (column: string): string => ctx.col("refs", column);
  const runsName = ctx.tableName("runs").name;
  const recordsName = ctx.tableName("records").name;
  const unique = `(${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")})`;

  const runJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${r("id")}, 'organizationId', ${alias}.${r("tenant")}, 'source', ${alias}.${r("source")}, 'status', ${alias}.${r("status")}, 'outcome', ${alias}.${r("outcome")}, 'plan', ${alias}.${r("plan")}, 'mapping', ${alias}.${r("mapping")}, 'counts', ${alias}.${r("counts")}, 'errors', ${alias}.${r("errors")}, 'dryRun', ${alias}.${r("dryRun")}, 'full', ${alias}.${r("full")}, 'inputChecksum', ${alias}.${r("inputChecksum")}, 'correlationId', ${alias}.${r("correlationId")}, 'mapperVersion', ${alias}.${r("mapperVersion")}, 'scopeAliases', ${alias}.${r("scopeAliases")}, 'leaseUntil', ${alias}.${r("leaseUntil")}, 'heartbeatAt', ${alias}.${r("heartbeatAt")}, 'createdBy', ${alias}.${r("createdBy")}, 'createdAt', ${alias}.${r("createdAt")}, 'startedAt', ${alias}.${r("startedAt")}, 'finishedAt', ${alias}.${r("finishedAt")}, 'issues', ${importIssueCounts(ctx, `${alias}.${r("id")}`)})`;

  const list = {
    name: "list_import_runs",
    from: runs,
    alias: "r",
    where: [
      `r.${r("tenant")} = list_import_runs.tenant`,
      filterAny("source", `r.${r("source")}`),
      filterAny("status", `r.${r("status")}::text`),
    ],
    keys: [
      { expr: `r.${r("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `r.${r("id")}`, dir: "desc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `r.${r("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `r.${r("id")}`, dir: "desc", type: "uuid" },
      ],
    },
    facets: { source: `r.${r("source")}`, status: `r.${r("status")}` },
    rowJson: runJson("r"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string): string =>
      fail("IMPORT_INVALID", message, "22023"),
  } as const;

  const status = `${r("status")} in ('pending', 'running', 'completed', 'failed', 'canceled')`;

  const tables = ctx.manages
    ? `create table if not exists ${runs} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("source")} text not null,
  ${r("status")} text not null default 'pending',
  ${r("mapping")} jsonb not null default '{}'::jsonb,
  ${r("counts")} jsonb not null default '{}'::jsonb,
  ${r("errors")} jsonb not null default '[]'::jsonb,
  ${r("createdBy")} uuid,
  ${r("createdAt")} timestamptz not null default now()
);
alter table ${runs} add column if not exists ${r("dryRun")} boolean not null default false;
alter table ${runs} add column if not exists ${r("diff")} jsonb not null default '[]'::jsonb;
alter table ${runs} add column if not exists ${r("full")} boolean not null default false;
alter table ${runs} add column if not exists ${r("inputChecksum")} text;
alter table ${runs} add column if not exists ${r("correlationId")} text;
alter table ${runs} add column if not exists ${r("mapperVersion")} text;
alter table ${runs} add column if not exists ${r("scopeAliases")} jsonb not null default '[]'::jsonb;
alter table ${runs} add column if not exists ${r("startedAt")} timestamptz;
alter table ${runs} add column if not exists ${r("finishedAt")} timestamptz;
alter table ${runs} add column if not exists ${r("plan")} jsonb;
alter table ${runs} add column if not exists ${r("outcome")} text;
alter table ${runs} add column if not exists ${r("leaseUntil")} timestamptz;
alter table ${runs} add column if not exists ${r("heartbeatAt")} timestamptz;
alter table ${runs} drop constraint if exists ${sqlIdent(`${runsName}_status_check`)};
${ensureCheck(runs, `bsb_${runsName}_status`, status)}
${lockTable(runs, { read: true })}
create index if not exists ${sqlIdent(`${runsName}_tenant_idx`)} on ${runs} (${r("tenant")});
-- One pending or running run per organization and source.
create unique index if not exists ${sqlIdent(`${runsName}_active_idx`)} on ${runs} (${r("tenant")}, ${r("source")}) where ${r("status")} in ('pending', 'running');

create table if not exists ${records} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("source")} text not null,
  ${x("scope")} text not null default '',
  ${x("entity")} text not null,
  ${x("externalKey")} text not null,
  ${x("role")} text not null default 'primary',
  ${x("subjectType")} text not null,
  ${x("subjectId")} text not null,
  ${x("contentHash")} text not null,
  ${x("firstRun")} uuid not null,
  ${x("lastRun")} uuid not null,
  ${x("subjectUpdatedAt")} timestamptz,
  ${x("sourceUpdatedAt")} timestamptz,
  ${x("ownedHash")} text,
  ${x("missingSince")} timestamptz,
  constraint ${sqlIdent(`${recordsName}_key`)} unique ${unique}
);
create index if not exists ${sqlIdent(`${recordsName}_subject_idx`)} on ${records} (${x("tenant")}, ${x("subjectType")}, ${x("subjectId")});
alter table ${records} add column if not exists ${x("ownedHash")} text;
alter table ${records} add column if not exists ${x("sourceUpdatedAt")} timestamptz;
${lockTable(records, { read: true })}
create table if not exists ${refs} (
  "id" uuid primary key default gen_random_uuid(),
  ${ref("tenant")} ${ctx.idType} not null,
  "kind" text not null,
  "key" text not null,
  "payload" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default now(),
  constraint import_refs_key unique (${ref("tenant")}, "kind", "key")
);
${lockTable(refs)}
${chunkTable(ctx, runs)}
${importIssuesTable(ctx)}`
    : "";

  const known = `array[${targets.map((target) => sqlString(target.entity)).join(", ")}]::text[]`;

  const writeArms = targets
    .map((target) => {
      const before =
        target.before === undefined
          ? ""
          : `        v_call := coalesce(${quotedTable(target.before)}(v_run_id, v_call, v_subject_id), v_call);\n`;

      const after =
        target.after === undefined
          ? ""
          : `\n        v_out := coalesce(${quotedTable(target.after)}(v_run_id, v_out, v_subject_id), v_out);`;

      return `      when ${sqlString(target.entity)} then
        v_subject_type := ${sqlString(target.subjectType)};
${before}        v_out := ${quotedTable(target.write)}(v_run_id, v_call, v_subject_id);${after}`;
    })
    .join("\n");

  const currentOwned = assignCase(
    targets,
    (target) => target.ownedHash,
    "v_owned",
    sqlString,
    quotedTable,
    `v_rec.${x("subjectId")}`,
  );

  const currentUpdated = assignCase(
    targets,
    (target) => target.updatedAt,
    "v_current",
    sqlString,
    quotedTable,
    `v_rec.${x("subjectId")}`,
  );

  const dispatch =
    targets.length === 0
      ? fail(
          "IMPORT_TARGET_UNKNOWN",
          "no import target for this entity",
          "22023",
        )
      : `case v_entity
${writeArms}
      else
        ${fail("IMPORT_TARGET_UNKNOWN", "no import target for this entity", "22023")}
    end case;`;

  const { batched, batchCondition, writeBlock, flushPending } = batchSql({
    targets,
    dispatch,
    records,
    unique,
    x,
    r,
  });

  const naturalLookup = naturalLookupOf(
    targets,
    sqlString,
    quotedTable,
    `v_run.${r("tenant")}`,
  );

  const resolvedRefs = refResolveSql(
    targets,
    sqlString,
    records,
    x("tenant"),
    x("source"),
    x("entity"),
    x("externalKey"),
    x("subjectId"),
  );

  const queue = ctx.enqueue(
    "imports",
    `jsonb_build_object('run', v_run.${r("id")}, 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk)`,
    `v_run.${r("id")}::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text`,
  );

  const bumped = (key: string): string =>
    `'${key}', coalesce(r.${r("counts")} -> v_entity ->> '${key}', '0')::integer + coalesce((v_result ->> '${key}')::integer, 0)`;

  const mergeCounts = `update ${runs} r set
    ${r("counts")} = jsonb_set(r.${r("counts")}, array[v_entity], jsonb_build_object(
      ${["inserted", "updated", "unchanged", "conflicted"].map(bumped).join(",\n      ")},
      'missing', coalesce((r.${r("counts")} -> v_entity ->> 'missing')::integer, 0)
    )),
    ${r("errors")} = r.${r("errors")} || coalesce(v_result -> 'errors', '[]'::jsonb),
    ${r("diff")} = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r.${r("diff")} || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r.${r("id")} = v_run_id;`;

  return `${schemaPreamble(ctx)}
${tables}
create or replace function ${ctx.fn("start_import_run")}(tenant ${ctx.idType}, source text, options jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_options jsonb := coalesce(start_import_run.options, '{}'::jsonb);
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("start_import_run.tenant", manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to import")}
  end if;
  if start_import_run.source is null or start_import_run.source = '' then
    ${fail("IMPORT_ITEM_INVALID", "an import run needs a source", "22023")}
  end if;
  if jsonb_typeof(coalesce(v_options -> 'scopeAliases', '[]'::jsonb)) <> 'array' then
    ${fail("IMPORT_ITEM_INVALID", "scopeAliases must be an array of { scope, of, entities }", "22023")}
  end if;
  begin
    insert into ${runs} as r (${r("tenant")}, ${r("source")}, ${r("mapping")}, ${r("dryRun")}, ${r("full")}, ${r("inputChecksum")}, ${r("correlationId")}, ${r("mapperVersion")}, ${r("scopeAliases")}, ${r("plan")}, ${r("leaseUntil")}, ${r("createdBy")})
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      nullif(v_options ->> 'mapperVersion', ''),
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
      v_options -> 'plan',
      now() + interval '30 seconds',
      auth.uid()
    )
    returning r.${r("id")} into v_id;
  exception when unique_violation then
    ${fail("IMPORT_RUN_ACTIVE", "an import of this source is already pending or running", "55P03")}
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${ctx.fn("start_import_run")}(${ctx.idType}, text, jsonb)`)}

-- The first release's entry point: a run without options.
create or replace function ${ctx.fn("start_import")}(tenant ${ctx.idType}, source text, mapping jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select ${ctx.fn("start_import_run")}(start_import.tenant, start_import.source, jsonb_build_object('mapping', coalesce(start_import.mapping, '{}'::jsonb)));
$$;
${userGrant(`${ctx.fn("start_import")}(${ctx.idType}, text, jsonb)`)}

create or replace function ${ctx.fn("get_import_run")}(id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run ${runs};
begin
  select * into v_run from ${runs} r where r.${r("id")} = get_import_run.id;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can(`v_run.${r("tenant")}`, manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to read this import")}
  end if;
  return ${runJson("v_run")};
end;
$$;
${userGrant(`${ctx.fn("get_import_run")}(uuid)`)}

-- Newest first. filters is { source, status (each a value or a list), sort,
-- direction, facet, count, limit, after, offset, paged, total, totalCap }
-- (ADR 0749).
create or replace function ${ctx.fn("list_import_runs")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_import_runs.filters, '{}'::jsonb);
  ${listDeclare(list)}
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("list_import_runs.tenant", manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to list imports")}
  end if;
  ${listBody(list)}
end;
$$;
${userGrant(`${ctx.fn("list_import_runs")}(${ctx.idType}, jsonb)`)}

create or replace function ${ctx.fn("cancel_import_run")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run ${runs};
begin
  select * into v_run from ${runs} r where r.${r("id")} = cancel_import_run.id for update;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can(`v_run.${r("tenant")}`, manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to cancel this import")}
  end if;
  if v_run.${r("status")} not in ('pending', 'running') then
    ${fail("IMPORT_RUN_NOT_RUNNING", "this import already finished", "55000")}
  end if;
  update ${runs} r set ${r("status")} = ${ctx.cast("runs", "status", "'canceled'")}, ${r("finishedAt")} = now()
  where r.${r("id")} = cancel_import_run.id;
${refreshRun("cancel_import_run.id")}  return true;
end;
$$;
${userGrant(`${ctx.fn("cancel_import_run")}(uuid)`)}

-- The run moves from pending to running before the first batch, so a run
-- that dies mid-way is visible as running rather than pending.
create or replace function ${ctx.fn("mark_import_running")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update ${runs} set ${r("status")} = 'running', ${r("startedAt")} = now()
  where ${r("id")} = mark_import_running.id and ${r("status")} = 'pending';
  if not found then
    ${fail("IMPORT_NOT_FOUND", "no pending import with this id", "P0002")}
  end if;
  return true;
end;
$$;
${serviceGrant(`${ctx.fn("mark_import_running")}(uuid)`)}

-- Closes a run whose rows the caller wrote itself (\`defineImport\` without a
-- target); \`finish_import_run\` closes a run that used \`import_upsert_batch\`.
create or replace function ${ctx.fn("finish_import")}(id uuid, status text, count integer, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_source text;
begin
  update ${runs} set ${r("status")} = ${ctx.cast("runs", "status", "finish_import.status")},
    ${r("finishedAt")} = now(),
    ${r("counts")} = case when finish_import.status = 'completed' then jsonb_build_object(${r("source")}, jsonb_build_object('inserted', finish_import.count, 'updated', 0, 'unchanged', 0, 'conflicted', 0, 'missing', 0)) else ${r("counts")} end,
    ${r("errors")} = case when finish_import.error is null then ${r("errors")} else ${r("errors")} || jsonb_build_array(jsonb_build_object('entity', ${r("source")}, 'key', null, 'code', 'IMPORT_ITEM_INVALID', 'message', finish_import.error)) end
  where ${r("id")} = finish_import.id
  returning ${r("tenant")}, ${r("source")} into v_tenant, v_source;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if finish_import.status = 'failed' then
    ${ctx.record({
      type: "import.failed",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'error', finish_import.error)`,
      subject: `'imports/' || finish_import.id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  else
    ${ctx.record({
      type: "import.completed",
      payload: `jsonb_build_object('organizationId', v_tenant, 'id', finish_import.id, 'count', finish_import.count)`,
      subject: `'imports/' || finish_import.id::text`,
      tenant: "v_tenant",
      audit: false,
    })}
  end if;
  return true;
end;
$$;
${serviceGrant(`${ctx.fn("finish_import")}(uuid, text, integer, text)`)}
${importIssueHelpers(ctx, manage)}${importIntegritySql(ctx)}${importSourcesSql(ctx)}

-- Writes the items of one entity: an unknown key inserts, an equal hash is
-- unchanged and writes nothing, a changed hash updates unless the row changed
-- after the last import (conflicted). Returns the counts and the item errors.
create or replace function ${ctx.fn("import_apply_batch")}(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run ${runs};
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec ${records};
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_conflict_keys jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
${batched.length === 0 ? "" : "  v_pending jsonb[] := '{}';\n  v_calls jsonb[] := '{}';\n  v_pending_keys text[] := '{}';\n  v_raw jsonb;\n  v_results jsonb[];\n  v_p jsonb;\n  v_i integer;\n"}begin
  select * into v_run from ${runs} r where r.${r("id")} = v_run_id;
  if v_entity <> all (${known}) then
    ${fail("IMPORT_TARGET_UNKNOWN", "no import target for this entity", "22023")}
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    ${fail("IMPORT_ITEM_INVALID", "items must be an array of { key, scope, data, refs }", "22023")}
  end if;

  v_ref_map := ${resolvedRefs.map};

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform ${ctx.fn("import_note_issue")}(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    ${
      batchCondition === "false"
        ? ""
        : `if v_scope || chr(31) || v_key = any (v_pending_keys) then
      ${flushPending}
    end if;`
    }

    begin
      v_done := false;
      select * into v_rec from ${records} x
      where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("scope")} = v_scope
        and x.${x("entity")} = v_entity and x.${x("externalKey")} = v_key and x.${x("role")} = 'primary';
      v_found := found;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec.${x("sourceUpdatedAt")} is not null and v_source_at <= v_rec.${x("sourceUpdatedAt")} then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := ${sha256HexSql("v_data::text")};
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        ${naturalLookup}
        if v_natural is not null then
          v_found := true;
          v_rec.${x("subjectId")} := v_natural;
          v_rec.${x("contentHash")} := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run.${r("scopeAliases")}) as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from ${records} x
            where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("scope")} = v_other
              and x.${x("entity")} = v_entity and x.${x("externalKey")} = v_key and x.${x("role")} = 'primary' and x.${x("contentHash")} = v_hash
          ) then
            insert into ${records} (${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")}, ${x("subjectType")}, ${x("subjectId")}, ${x("contentHash")}, ${x("firstRun")}, ${x("lastRun")}, ${x("subjectUpdatedAt")})
            select x.${x("tenant")}, x.${x("source")}, v_scope, x.${x("entity")}, x.${x("externalKey")}, x.${x("role")}, x.${x("subjectType")}, x.${x("subjectId")}, x.${x("contentHash")}, v_run_id, v_run_id, x.${x("subjectUpdatedAt")}
            from ${records} x
            where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("scope")} = v_other
              and x.${x("entity")} = v_entity and x.${x("externalKey")} = v_key
            on conflict ${unique} do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec.${x("contentHash")} = v_hash then
        update ${records} x set ${x("lastRun")} = v_run_id, ${x("missingSince")} = null
        where x.${x("tenant")} = v_rec.${x("tenant")} and x.${x("source")} = v_rec.${x("source")} and x.${x("scope")} = v_rec.${x("scope")}
          and x.${x("entity")} = v_rec.${x("entity")} and x.${x("externalKey")} = v_rec.${x("externalKey")}
          and (x.${x("lastRun")} is distinct from v_run_id or x.${x("missingSince")} is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        ${currentUpdated}
        ${currentOwned}
        if v_owned is not null and v_rec.${x("ownedHash")} is not null and v_owned is distinct from v_rec.${x("ownedHash")} then
          update ${records} x set ${x("lastRun")} = v_run_id, ${x("missingSince")} = null
          where x.${x("id")} = v_rec.${x("id")};
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec.${x("subjectUpdatedAt")} is not null and v_current > v_rec.${x("subjectUpdatedAt")} then
          update ${records} x set ${x("lastRun")} = v_run_id, ${x("subjectUpdatedAt")} = v_current, ${x("ownedHash")} = v_owned
          where x.${x("id")} = v_rec.${x("id")};
        elsif v_owned is null and v_current is not null and v_rec.${x("subjectUpdatedAt")} is not null and v_current > v_rec.${x("subjectUpdatedAt")} then
          update ${records} x set ${x("lastRun")} = v_run_id, ${x("missingSince")} = null
          where x.${x("id")} = v_rec.${x("id")};
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        if jsonb_array_length(v_conflict_keys) < 100 then
          v_conflict_keys := v_conflict_keys || to_jsonb(v_key);
        end if;
        perform ${ctx.fn("import_note_issue")}(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform ${ctx.fn("import_clear_issues")}(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run.${r("dryRun")} and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec.${x("subjectId")} else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run.${r("tenant")}, 'scope', v_scope);
        ${resolvedRefs.attach}
        ${writeBlock}
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform ${ctx.fn("import_note_issue")}(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  ${flushPending}

  perform ${ctx.fn("import_note_warnings")}(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_conflict_keys) > 0 then jsonb_build_object('conflictKeys', v_conflict_keys) else '{}'::jsonb end || case when jsonb_array_length(v_diff) > 0 then jsonb_build_object('diff', v_diff) else '{}'::jsonb end || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$$;
${serviceGrant(`${ctx.fn("import_apply_batch")}(uuid, text, jsonb)`)}

-- Turns import mode on for the rest of the transaction (ADR 0141): the outbox
-- applies the imports.events policy, the audit log tags entries as
-- integration with the correlation id import:<run> (imports.audit decides rows
-- or one summary per entity) and ctx.importing() guards skip their side
-- effects. The setting is transaction-local and better_supabase.import_run()
-- only reports it to the service role, so no user session can turn it on.
create or replace function ${ctx.fn("begin_import_session")}(run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_status text;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("IMPORT_FORBIDDEN", "only the service role can begin an import session")}
  end if;
  select r.${r("status")}::text into v_status from ${runs} r where r.${r("id")} = begin_import_session.run;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if v_status <> 'running' then
    ${fail("IMPORT_RUN_NOT_RUNNING", "the import is not running", "55000")}
  end if;
  perform set_config('better_supabase.import_run', begin_import_session.run::text, true);
  perform set_config('better_supabase.correlation_id', 'import:' || begin_import_session.run::text, true);
  perform set_config('better_supabase.import_events', ${eventsPolicy}, true);
  perform set_config('better_supabase.import_audit', '${auditMode}', true);
  return begin_import_session.run;
end;
$$;
${serviceGrant(`${ctx.fn("begin_import_session")}(uuid)`)}

-- The single write path of an import (service role). It begins the import
-- session for its writes and restores the caller's settings afterwards. A dry
-- run writes inside a subtransaction it rolls back, then keeps the counts.
create or replace function ${ctx.fn("import_upsert_batch")}(run uuid, entity text, items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run ${runs};
  v_result jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from ${runs} r where r.${r("id")} = v_run_id;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if v_run.${r("status")} <> 'running' then
    ${fail("IMPORT_RUN_NOT_RUNNING", "the import is not running", "55000")}
  end if;
  if coalesce((v_run.${r("plan")} ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run.${r("plan")} -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run.${r("plan")} -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run.${r("plan")} -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join ${ctx.table("chunks")} c on c.${ctx.col("chunks", "run")} = v_run_id
          and c.${ctx.col("chunks", "entity")} = dep.entity and c.${ctx.col("chunks", "status")} <> 'done'
        where earlier.n < w.n)) then
    ${fail("IMPORT_DEPENDENCY_OPEN", "an earlier import wave still has open chunks", "55000")}
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform ${ctx.fn("begin_import_session")}(v_run_id);
${searchDeferral ? "  perform set_config('better_supabase.search_deferred', 'on', true);\n" : ""}
  if v_run.${r("dryRun")} then
    begin
      v_result := ${ctx.fn("import_apply_batch")}(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = '${DRY_RUN_STATE}';
    exception when sqlstate '${DRY_RUN_STATE}' then
      null;
    end;
  else
    v_result := ${ctx.fn("import_apply_batch")}(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  ${mergeCounts}
  return v_result || jsonb_build_object('dryRun', v_run.${r("dryRun")});
end;
$$;
${serviceGrant(`${ctx.fn("import_upsert_batch")}(uuid, text, jsonb)`)}

-- Bulk external key to subject. keys is an array of text, or of { key, scope,
-- role }; a scope that aliases another resolves through it.
create or replace function ${ctx.fn("import_resolve")}(run uuid, entity text, keys jsonb)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs};
begin
  select * into v_run from ${runs} r where r.${r("id")} = import_resolve.run;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if jsonb_typeof(import_resolve.keys) <> 'array' then
    ${fail("IMPORT_ITEM_INVALID", "keys must be an array", "22023")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', q.key, 'scope', q.scope, 'role', q.role, 'subjectType', m.${x("subjectType")}, 'subjectId', m.${x("subjectId")}) order by q.ord)
    from (
      select k.ord,
        case when jsonb_typeof(k.value) = 'string' then k.value #>> '{}' else k.value ->> 'key' end as key,
        case when jsonb_typeof(k.value) = 'string' then '' else coalesce(k.value ->> 'scope', '') end as scope,
        case when jsonb_typeof(k.value) = 'string' then 'primary' else coalesce(k.value ->> 'role', 'primary') end as role
      from jsonb_array_elements(import_resolve.keys) with ordinality k(value, ord)
    ) q
    join lateral (
      select x.${x("subjectType")}, x.${x("subjectId")}
      from ${records} x
      where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")}
        and x.${x("entity")} = import_resolve.entity and x.${x("externalKey")} = q.key and x.${x("role")} = q.role
        and (x.${x("scope")} = q.scope or x.${x("scope")} in (
          select a."of" from jsonb_to_recordset(v_run.${r("scopeAliases")}) as a(scope text, "of" text, entities jsonb)
          where a.scope = q.scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? import_resolve.entity)
        ))
      order by (x.${x("scope")} = q.scope) desc
      limit 1
    ) m on true
  ), '[]'::jsonb);
end;
$$;
${serviceGrant(`${ctx.fn("import_resolve")}(uuid, text, jsonb)`)}

-- Closes a run that wrote through import_upsert_batch. A full run marks the
-- records of its entities it didn't see, and never deletes them.
create or replace function ${ctx.fn("finish_import_run")}(run uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run ${runs};
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from ${runs} r where r.${r("id")} = v_run_id for update;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if v_run.${r("status")} <> 'running' then
    ${fail("IMPORT_RUN_NOT_RUNNING", "the import is not running", "55000")}
  end if;
  v_counts := v_run.${r("counts")};

  if v_run.${r("full")} then
    for v_entity in select k.key from jsonb_object_keys(v_run.${r("counts")}) k(key) loop
      select count(*)::integer into v_missing from ${records} x
      where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("entity")} = v_entity
        and x.${x("role")} = 'primary' and x.${x("lastRun")} <> v_run_id
        and x.${x("scope")} in (select y.${x("scope")} from ${records} y where y.${x("tenant")} = v_run.${r("tenant")} and y.${x("source")} = v_run.${r("source")} and y.${x("entity")} = v_entity and y.${x("lastRun")} = v_run_id);
      if not v_run.${r("dryRun")} then
        update ${records} x set ${x("missingSince")} = coalesce(x.${x("missingSince")}, now())
        where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("entity")} = v_entity
          and x.${x("lastRun")} <> v_run_id
          and x.${x("scope")} in (select y.${x("scope")} from ${records} y where y.${x("tenant")} = v_run.${r("tenant")} and y.${x("source")} = v_run.${r("source")} and y.${x("entity")} = v_entity and y.${x("lastRun")} = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run.${r("plan")} is not null and jsonb_typeof(v_run.${r("plan")}) = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run.${r("plan")}) k(key) loop
      v_expected := coalesce((v_run.${r("plan")} ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (
    jsonb_array_length(coalesce(v_run.${r("errors")}, '[]'::jsonb)) > 0
    or exists (
      select 1 from jsonb_each(coalesce(v_counts, '{}'::jsonb)) v_entity_counts(key, value)
      where coalesce((v_entity_counts.value ->> 'conflicted')::integer, 0) > 0
    )
  ) then
    v_outcome := 'completed_with_issues';
  end if;

  update ${runs} r set ${r("status")} = ${ctx.cast("runs", "status", "'completed'")}, ${r("outcome")} = v_outcome, ${r("finishedAt")} = now(), ${r("counts")} = v_counts
  where r.${r("id")} = v_run_id;

  if not v_run.${r("dryRun")} then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      ${ctx.record({
        type: "import.entity_completed",
        payload: `jsonb_build_object('organizationId', v_run.${r("tenant")}, 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity)`,
        subject: `'imports/' || v_run_id::text`,
        tenant: `v_run.${r("tenant")}`,
        audit: false,
      })}${
        auditMode === "summary"
          ? `
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        ${ctx.audit({
          type: "import.entity_completed",
          payload: `jsonb_build_object('organizationId', v_run.${r("tenant")}, 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity)`,
          subject: `'imports/' || v_run_id::text`,
          tenant: `v_run.${r("tenant")}`,
          key: `'import:' || v_run_id::text || ':' || v_entity`,
          audit: {
            category: "integration",
            targetType: "import",
            recordId: "v_run_id::text",
            targetLabel: "v_entity",
            summary: `'imported ' || v_entity`,
            actorKind: "'integration'",
            correlationId: "'import:' || v_run_id::text",
          },
        })}
      end if;`
          : ""
      }
    end loop;
    ${ctx.record({
      type: "import.completed",
      payload: `jsonb_build_object('organizationId', v_run.${r("tenant")}, 'id', v_run_id, 'count', v_total)`,
      subject: `'imports/' || v_run_id::text`,
      tenant: `v_run.${r("tenant")}`,
      audit: false,
    })}
  end if;
${refreshRun("v_run_id")}  return v_counts;
end;
$$;
${serviceGrant(`${ctx.fn("finish_import_run")}(uuid)`)}
${importLifecycleSql(
  ctx,
  targets.map((target) => target.entity),
)}
${rebaseImportSql(
  ctx,
  readerCaseOf(
    targets,
    (target) => target.updatedAt,
    sqlString,
    quotedTable,
    `x.${x("subjectId")}`,
    `x.${x("entity")}`,
  ),
  readerCaseOf(
    targets,
    (target) => target.ownedHash,
    sqlString,
    quotedTable,
    `x.${x("subjectId")}`,
    `x.${x("entity")}`,
  ),
)}

-- Queues one job per chunk of an entity's items, so a worker writes a large
-- import in batches; the dedupe key makes a retry harmless.
create or replace function ${ctx.fn("enqueue_import_chunks")}(run uuid, entity text, chunks integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_run ${runs};
  v_chunk integer;
begin
  select * into v_run from ${runs} r where r.${r("id")} = enqueue_import_chunks.run;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    ${fail("IMPORT_ITEM_INVALID", "chunks must be at least 1", "22023")}
  end if;
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    ${queue}
  end loop;
  return enqueue_import_chunks.chunks;
end;
$$;
${serviceGrant(`${ctx.fn("enqueue_import_chunks")}(uuid, text, integer)`)}
${chunkFunctions(ctx, runs)}${hashFunctions(ctx, runs)}`;
}

export const IMPORTS: BlockSqlDefinition = {
  name: "imports",
  scopes: ["tenant"],
  title: "Imports",
  description:
    "Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.",
  requires: ["memberships", "permissions", "queue"],
  integrates: [
    "attachments",
    "contacts",
    "invoices",
    "ledger",
    "outbox",
    "search",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  names: IMPORT_NAMES,
  contract,
  build,
};
