import type { ImportsEvents } from "../../blocks/imports/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import {
  ensureCheck,
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  serviceGrant,
  sha256Hex,
  userGrant,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The SQLSTATE a dry run raises to roll its writes back. */
const DRY_RUN_STATE = "BSDRY";

const FUNCTION_NAME: RegExp = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;
const ENTITY_NAME: RegExp = /^[a-z][a-z0-9_.:-]*$/i;

const EVENTS: BlockSqlEvents<ImportsEvents> = {
  "import.completed": {
    subject: "imports",
    payload: ["organizationId", "id", "count"],
  },
  "import.failed": {
    subject: "imports",
    payload: ["organizationId", "id", "error"],
  },
  "import.entity_completed": {
    subject: "imports",
    payload: ["organizationId", "id", "entity", "counts"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["targets"],
  migrations: [
    {
      from: 1,
      description:
        "An import run names its source instead of its kind (ADR 0141).",
      table: "runs",
      columns: { source: "kind" },
    },
  ],
  tables: {
    runs: {
      name: "import_runs",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        source: "source",
        status: "status",
        mapping: "mapping",
        counts: "counts",
        errors: "errors",
        dryRun: "dry_run",
        full: "full",
        inputChecksum: "input_checksum",
        correlationId: "correlation_id",
        scopeAliases: "scope_aliases",
        createdBy: "created_by",
        createdAt: "created_at",
        startedAt: "started_at",
        finishedAt: "finished_at",
      },
      typed: ["status"],
    },
    records: {
      name: "import_records",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        source: "source",
        scope: "scope",
        entity: "entity",
        externalKey: "external_key",
        role: "role",
        subjectType: "subject_type",
        subjectId: "subject_id",
        contentHash: "content_hash",
        firstRun: "first_run_id",
        lastRun: "last_run_id",
        subjectUpdatedAt: "subject_updated_at_at_import",
        missingSince: "missing_since",
      },
    },
  },
};

/**
 * Every target the module dispatches to: the contributions of the blocks that
 * use `imports`, then the app's own from `blocks.imports.options.targets`.
 */
function targetsOf(ctx: BlockSqlContext): readonly ImportTargetContribution[] {
  const where = "blocks['imports'].options.targets";
  const raw: unknown = ctx.option("targets") ?? {};

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(`${where} must map entity names to targets`);
  }

  const own: ImportTargetContribution[] = [];

  for (const [entity, value] of new Map<string, unknown>(Object.entries(raw))) {
    if (!ENTITY_NAME.test(entity)) {
      throw new TypeError(`${where}: "${entity}" is not a valid entity name`);
    }

    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError(
        `${where}.${entity} must be { subjectType, write, updatedAt? }`,
      );
    }

    const entry = new Map<string, unknown>(Object.entries(value));
    const subjectType = entry.get("subjectType");
    const write = entry.get("write");
    const updatedAt = entry.get("updatedAt");

    if (typeof subjectType !== "string" || subjectType === "") {
      throw new TypeError(`${where}.${entity}.subjectType must be a string`);
    }

    if (typeof write !== "string" || !FUNCTION_NAME.test(write)) {
      throw new TypeError(
        `${where}.${entity}.write must be a "schema.function" name in lowercase`,
      );
    }

    if (
      updatedAt !== undefined &&
      (typeof updatedAt !== "string" || !FUNCTION_NAME.test(updatedAt))
    ) {
      throw new TypeError(
        `${where}.${entity}.updatedAt must be a "schema.function" name in lowercase`,
      );
    }

    own.push({
      entity,
      subjectType,
      write,
      ...(updatedAt === undefined ? {} : { updatedAt }),
    });
  }

  return uniqueContributions(
    "imports",
    [...ctx.contributions("imports"), ...own],
    (target) => target.entity,
  );
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
  const runsName = ctx.tableName("runs").name;
  const recordsName = ctx.tableName("records").name;
  const unique = `(${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")})`;

  const runJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${r("id")}, 'organizationId', ${alias}.${r("tenant")}, 'source', ${alias}.${r("source")}, 'status', ${alias}.${r("status")}, 'mapping', ${alias}.${r("mapping")}, 'counts', ${alias}.${r("counts")}, 'errors', ${alias}.${r("errors")}, 'dryRun', ${alias}.${r("dryRun")}, 'full', ${alias}.${r("full")}, 'inputChecksum', ${alias}.${r("inputChecksum")}, 'correlationId', ${alias}.${r("correlationId")}, 'scopeAliases', ${alias}.${r("scopeAliases")}, 'createdBy', ${alias}.${r("createdBy")}, 'createdAt', ${alias}.${r("createdAt")}, 'startedAt', ${alias}.${r("startedAt")}, 'finishedAt', ${alias}.${r("finishedAt")})`;

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
alter table ${runs} add column if not exists ${r("full")} boolean not null default false;
alter table ${runs} add column if not exists ${r("inputChecksum")} text;
alter table ${runs} add column if not exists ${r("correlationId")} text;
alter table ${runs} add column if not exists ${r("scopeAliases")} jsonb not null default '[]'::jsonb;
alter table ${runs} add column if not exists ${r("startedAt")} timestamptz;
alter table ${runs} add column if not exists ${r("finishedAt")} timestamptz;
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
  ${x("missingSince")} timestamptz,
  constraint ${sqlIdent(`${recordsName}_key`)} unique ${unique}
);
create index if not exists ${sqlIdent(`${recordsName}_subject_idx`)} on ${records} (${x("tenant")}, ${x("subjectType")}, ${x("subjectId")});
${lockTable(records, { read: true })}
`
    : "";

  const known = `array[${targets.map((target) => sqlString(target.entity)).join(", ")}]::text[]`;

  const writeArms = targets
    .map(
      (target) => `      when ${sqlString(target.entity)} then
        v_subject_type := ${sqlString(target.subjectType)};
        v_out := ${quotedTable(target.write)}(v_run_id, v_call, v_subject_id);`,
    )
    .join("\n");

  const updatedArms = targets
    .filter((target) => target.updatedAt !== undefined)
    .map(
      (target) => `        when ${sqlString(target.entity)} then
          v_current := ${quotedTable(target.updatedAt ?? "")}(v_rec.${x("subjectId")});`,
    )
    .join("\n");

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

  const currentUpdated =
    updatedArms === ""
      ? "null;"
      : `case v_entity
${updatedArms}
          else null;
        end case;`;

  const queue = ctx.enqueue(
    "'imports'",
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
    ${r("errors")} = r.${r("errors")} || coalesce(v_result -> 'errors', '[]'::jsonb)
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
    insert into ${runs} as r (${r("tenant")}, ${r("source")}, ${r("mapping")}, ${r("dryRun")}, ${r("full")}, ${r("inputChecksum")}, ${r("correlationId")}, ${r("scopeAliases")}, ${r("createdBy")})
    values (
      start_import_run.tenant,
      start_import_run.source,
      coalesce(v_options -> 'mapping', '{}'::jsonb),
      coalesce((v_options ->> 'dryRun')::boolean, false),
      coalesce((v_options ->> 'full')::boolean, false),
      v_options ->> 'inputChecksum',
      v_options ->> 'correlationId',
      coalesce(v_options -> 'scopeAliases', '[]'::jsonb),
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

create or replace function ${ctx.fn("list_import_runs")}(tenant ${ctx.idType}, source text default null, status text default null, row_limit integer default 50)
returns setof jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("list_import_runs.tenant", manage)}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to list imports")}
  end if;
  return query
    select ${runJson("r")}
    from ${runs} r
    where r.${r("tenant")} = list_import_runs.tenant
      and (list_import_runs.source is null or r.${r("source")} = list_import_runs.source)
      and (list_import_runs.status is null or r.${r("status")} = list_import_runs.status)
    order by r.${r("createdAt")} desc, r.${r("id")} desc
    limit least(greatest(coalesce(list_import_runs.row_limit, 50), 1), 200);
end;
$$;
${userGrant(`${ctx.fn("list_import_runs")}(${ctx.idType}, text, text, integer)`)}

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
  return true;
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
  v_rec ${records};
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from ${runs} r where r.${r("id")} = v_run_id;
  if v_entity <> all (${known}) then
    ${fail("IMPORT_TARGET_UNKNOWN", "no import target for this entity", "22023")}
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    ${fail("IMPORT_ITEM_INVALID", "items must be an array of { key, scope, data, refs }", "22023")}
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := ${sha256Hex("v_data::text")};

    begin
      v_done := false;
      select * into v_rec from ${records} x
      where x.${x("tenant")} = v_run.${r("tenant")} and x.${x("source")} = v_run.${r("source")} and x.${x("scope")} = v_scope
        and x.${x("entity")} = v_entity and x.${x("externalKey")} = v_key and x.${x("role")} = 'primary';
      v_found := found;

      if not v_found then
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
        ${currentUpdated}
        if v_current is not null and v_rec.${x("subjectUpdatedAt")} is not null and v_current > v_rec.${x("subjectUpdatedAt")} then
          update ${records} x set ${x("lastRun")} = v_run_id, ${x("missingSince")} = null
          where x.${x("id")} = v_rec.${x("id")};
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec.${x("subjectId")} else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run.${r("tenant")}, 'scope', v_scope);
        ${dispatch}

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          ${fail("IMPORT_ITEM_INVALID", "the import target returned no primary subject", "22023")}
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          insert into ${records} (${x("tenant")}, ${x("source")}, ${x("scope")}, ${x("entity")}, ${x("externalKey")}, ${x("role")}, ${x("subjectType")}, ${x("subjectId")}, ${x("contentHash")}, ${x("firstRun")}, ${x("lastRun")}, ${x("subjectUpdatedAt")}, ${x("missingSince")})
          values (
            v_run.${r("tenant")}, v_run.${r("source")}, v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ${unique} do update set
            ${x("subjectType")} = excluded.${x("subjectType")},
            ${x("subjectId")} = excluded.${x("subjectId")},
            ${x("contentHash")} = excluded.${x("contentHash")},
            ${x("lastRun")} = excluded.${x("lastRun")},
            ${x("subjectUpdatedAt")} = excluded.${x("subjectUpdatedAt")},
            ${x("missingSince")} = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors);
end;
$$;
${serviceGrant(`${ctx.fn("import_apply_batch")}(uuid, text, jsonb)`)}

-- The single write path of an import (service role). A dry run writes inside a
-- subtransaction it rolls back, then keeps the counts.
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
begin
  select * into v_run from ${runs} r where r.${r("id")} = v_run_id for update;
  if not found then
    ${fail("IMPORT_NOT_FOUND", "import not found", "P0002")}
  end if;
  if v_run.${r("status")} <> 'running' then
    ${fail("IMPORT_RUN_NOT_RUNNING", "the import is not running", "55000")}
  end if;

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

  update ${runs} r set ${r("status")} = ${ctx.cast("runs", "status", "'completed'")}, ${r("finishedAt")} = now(), ${r("counts")} = v_counts
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
      })}
    end loop;
    ${ctx.record({
      type: "import.completed",
      payload: `jsonb_build_object('organizationId', v_run.${r("tenant")}, 'id', v_run_id, 'count', v_total)`,
      subject: `'imports/' || v_run_id::text`,
      tenant: `v_run.${r("tenant")}`,
      audit: false,
    })}
  end if;
  return v_counts;
end;
$$;
${serviceGrant(`${ctx.fn("finish_import_run")}(uuid)`)}

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
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "start_import", args: ["{id}", "text", "jsonb"], returns: "jsonb" },
    {
      name: "start_import_run",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_import_run", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_import_runs",
      args: ["{id}", "text", "text", "integer"],
      returns: "setof jsonb",
    },
    { name: "cancel_import_run", args: ["uuid"], returns: "boolean" },
    { name: "mark_import_running", args: ["uuid"], returns: "boolean" },
    {
      name: "finish_import",
      args: ["uuid", "text", "integer", "text"],
      returns: "boolean",
    },
    {
      name: "import_upsert_batch",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "import_resolve",
      args: ["uuid", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "finish_import_run", args: ["uuid"], returns: "jsonb" },
    {
      name: "enqueue_import_chunks",
      args: ["uuid", "text", "integer"],
      returns: "integer",
    },
  ];
}

export const IMPORTS: BlockSqlDefinition = {
  name: "imports",
  scopes: ["tenant"],
  title: "Imports",
  description:
    "Import runs and the external record map. import_upsert_batch writes items through the targets blocks and the app register, skips equal content, reports rows a user changed since the last import and marks missing keys on full runs. The dry run, parsing and mapping live in TypeScript.",
  requires: ["memberships", "permissions", "queue"],
  integrates: ["attachments", "outbox"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  names: NAMES,
  contract,
  build,
};
