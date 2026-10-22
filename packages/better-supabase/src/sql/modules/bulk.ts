import type { BulkEvents } from "../../blocks/bulk/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

/** The actions every install knows, each backed by the block that owns it. */
export const BULK_ACTIONS = {
  "tags.set": "tags",
  "stateMachine.transition": "state-machine",
  "relations.link": "relations",
  "trash.trash": "trash",
  "collections.add": "collections",
  "appTables.set": "app-tables",
} as const;

/**
 * The app-tables function `appTables.set` calls, created with the app tables in
 * `public`.
 */
export const APP_TABLE_SET = "app_table_set";

const ACTION_NAME: RegExp = /^[a-z][A-Za-z0-9]*\.[a-z][A-Za-z0-9]*$/;
const FUNCTION_NAME: RegExp = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;
const DEFAULT_LIMIT = 500;
const MAX_RUN = 100_000;
const DEFAULT_CHUNK = 200;

const EVENTS: BlockSqlEvents<BulkEvents> = {
  "bulk_run.completed": {
    subject: "bulk-runs",
    payload: ["organizationId", "id", "kind", "status", "count", "failed"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["limit", "actions"],
  tables: {
    runs: {
      name: "bulk_runs",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        action: "action",
        args: "args",
        ids: "ids",
        position: "position",
        succeeded: "succeeded",
        failed: "failed",
        results: "results",
        status: "status",
        createdBy: "created_by",
        createdAt: "created_at",
        finishedAt: "finished_at",
      },
    },
  },
};

/**
 * `options.actions`: an app's own actions, each a `schema.function(tenant,
 * subject_type, id, args)`.
 */
function bulkActions(ctx: BlockSqlContext): ReadonlyMap<string, string> {
  const where = "blocks.bulk.options.actions";
  const raw: unknown = ctx.option("actions") ?? {};

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(`${where} must map action names to functions`);
  }

  const actions = new Map<string, string>();

  for (const [name, value] of new Map<string, unknown>(Object.entries(raw))) {
    if (!ACTION_NAME.test(name)) {
      throw new TypeError(
        `${where}: "${name}" must look like "block.method" (letters and digits)`,
      );
    }

    if (name in BULK_ACTIONS) {
      throw new TypeError(`${where}: "${name}" is a built-in action`);
    }

    if (typeof value !== "string" || !FUNCTION_NAME.test(value)) {
      throw new TypeError(
        `${where}.${name} must be a "schema.function" name in lowercase`,
      );
    }

    actions.set(name, value);
  }

  return actions;
}

function dispatch(
  ctx: BlockSqlContext,
  custom: ReadonlyMap<string, string>,
): string {
  const arms: string[] = [];

  if (ctx.installed("tags")) {
    const tags = ctx.of("tags");
    arms.push(`    when 'tags.set' then
      for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'add', '[]'::jsonb)) loop
        perform ${tags.fn("tag")}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
      end loop;
      for v_tag in select value::uuid from jsonb_array_elements_text(coalesce(bulk_row.args -> 'remove', '[]'::jsonb)) loop
        perform ${tags.fn("untag")}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, v_tag);
      end loop;`);
  }

  if (ctx.installed("state-machine")) {
    arms.push(`    when 'stateMachine.transition' then
      perform ${ctx.of("state-machine").fn("transition")}(bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'to', bulk_row.args ->> 'reason');`);
  }

  if (ctx.installed("relations")) {
    arms.push(`    when 'relations.link' then
      perform ${ctx.of("relations").fn("link")}(bulk_row.tenant, bulk_row.args ->> 'kind', bulk_row.subject_type, bulk_row.subject_id, bulk_row.args ->> 'targetType', bulk_row.args ->> 'targetId', bulk_row.args -> 'data');`);
  }

  if (ctx.installed("trash")) {
    arms.push(`    when 'trash.trash' then
      perform ${ctx.of("trash").fn("trash")}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id);`);
  }

  if (ctx.installed("collections")) {
    arms.push(`    when 'collections.add' then
      perform ${ctx.of("collections").fn("add_collection_entries")}((bulk_row.args ->> 'collectionId')::uuid, array[bulk_row.subject_id], bulk_row.subject_type);`);
  }

  if (ctx.appTables.size > 0) {
    arms.push(`    when 'appTables.set' then
      perform public.${sqlIdent(APP_TABLE_SET)}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, bulk_row.args);`);
  }

  for (const [name, target] of custom) {
    arms.push(`    when ${sqlString(name)} then
      perform ${quotedTable(target)}(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, bulk_row.args);`);
  }

  const unknown = fail("BULK_ACTION_UNKNOWN", "unknown bulk action", "22023");

  if (arms.length === 0) {
    return unknown;
  }

  return `case bulk_row.action
${arms.join("\n")}
    else
      ${unknown}
  end case;`;
}

/**
 * The PL/pgSQL loop that runs `v_chunk` row by row into `v_results`, `v_ok` and
 * `v_failed`.
 */
function rowLoop(
  ctx: BlockSqlContext,
  tenant: string,
  subjectType: string,
  action: string,
  args: string,
  atomic: string,
): string {
  return `foreach v_id in array v_chunk loop
    begin
      perform ${ctx.fn("bulk_row")}(${tenant}, ${subjectType}, v_id, ${action}, ${args});
      v_ok := v_ok + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', true));
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint, v_state = returned_sqlstate;
      if ${atomic} then
        raise exception using message = v_message, hint = coalesce(v_hint, ''), errcode = v_state;
      end if;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'error', jsonb_build_object('code', nullif(v_hint, ''), 'message', v_message, 'sqlstate', v_state)));
    end;
  end loop;`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const runs = ctx.table("runs");
  const c = (name: string): string => ctx.col("runs", name);
  const run = ctx.permission("run", OPERATIONS["bulk.run"]);
  const limit = ctx.number("limit", DEFAULT_LIMIT);

  if (!Number.isInteger(limit) || limit < 1 || limit > 10_000) {
    throw new TypeError(
      "blocks.bulk.options.limit must be an integer from 1 to 10000",
    );
  }

  const custom = bulkActions(ctx);
  const background = ctx.installed("jobs");

  const known = [
    ...Object.entries(BULK_ACTIONS)
      .filter(([, module]) =>
        module === "app-tables"
          ? ctx.appTables.size > 0
          : ctx.installed(module),
      )
      .map(([name]) => name),
    ...custom.keys(),
  ];

  const knownList =
    known.length === 0
      ? "array[]::text[]"
      : `array[${known.map(sqlString).join(", ")}]`;

  const tables = ctx.manages
    ? `create table if not exists ${runs} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("action")} text not null,
  ${c("args")} jsonb not null default '{}'::jsonb,
  ${c("ids")} text[] not null,
  ${c("position")} integer not null default 0,
  ${c("succeeded")} integer not null default 0,
  ${c("failed")} integer not null default 0,
  ${c("results")} jsonb not null default '[]'::jsonb,
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'running', 'completed', 'failed')),
  ${c("createdBy")} uuid not null,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("finishedAt")} timestamptz
);
create index if not exists bulk_runs_created_by_idx on ${runs} (${c("createdBy")}, ${c("createdAt")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("runs").name}_tenant_idx`)} on ${runs} (${c("tenant")});
${lockTable(runs, { read: true })}
drop policy if exists bulk_runs_read on ${runs};
create policy bulk_runs_read on ${runs} for select to authenticated
  using (${c("createdBy")} = (select auth.uid()));
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
create or replace function ${ctx.fn("bulk_row")}(tenant ${ctx.idType}, subject_type text, subject_id text, action text, args jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_tag uuid;
begin
  ${dispatch(ctx, custom)}
end;
$$;
${userGrant(`${ctx.fn("bulk_row")}(${ctx.idType}, text, text, text, jsonb)`)}

create or replace function ${ctx.fn("bulk_apply")}(tenant ${ctx.idType}, subject_type text, ids text[], action text, args jsonb, atomic boolean)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_chunk text[] := coalesce(bulk_apply.ids, array[]::text[]);
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
begin
  if not ${ctx.scope.can("bulk_apply.tenant", run)} then
    ${fail("BULK_FORBIDDEN", "not allowed to run bulk actions")}
  end if;
  if not (bulk_apply.action = any (${knownList})) then
    ${fail("BULK_ACTION_UNKNOWN", "unknown bulk action", "22023")}
  end if;
  if cardinality(v_chunk) > ${String(limit)} then
    ${fail("BULK_TOO_MANY", `more than ${String(limit)} rows; start a background run`, "22023")}
  end if;
  ${rowLoop(ctx, "bulk_apply.tenant", "bulk_apply.subject_type", "bulk_apply.action", "coalesce(bulk_apply.args, '{}'::jsonb)", "coalesce(bulk_apply.atomic, false)")}
  return jsonb_build_object('total', cardinality(v_chunk), 'succeeded', v_ok, 'failed', v_failed, 'results', v_results);
end;
$$;
${userGrant(`${ctx.fn("bulk_apply")}(${ctx.idType}, text, text[], text, jsonb, boolean)`)}

create or replace function ${ctx.fn("start_bulk")}(tenant ${ctx.idType}, subject_type text, ids text[], action text, args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_total integer := cardinality(coalesce(start_bulk.ids, array[]::text[]));
begin
  if auth.uid() is null or not ${ctx.scope.can("start_bulk.tenant", run)} then
    ${fail("BULK_FORBIDDEN", "not allowed to run bulk actions")}
  end if;
  if not (start_bulk.action = any (${knownList})) then
    ${fail("BULK_ACTION_UNKNOWN", "unknown bulk action", "22023")}
  end if;
  if v_total > ${String(MAX_RUN)} then
    ${fail("BULK_TOO_MANY", `a background run takes at most ${String(MAX_RUN)} rows`, "22023")}
  end if;
  ${
    background
      ? ""
      : fail(
          "BULK_NO_JOBS",
          "background bulk runs need the jobs module",
          "0A000",
        )
  }
  insert into ${runs} (${c("tenant")}, ${c("subjectType")}, ${c("action")}, ${c("args")}, ${c("ids")}, ${c("createdBy")})
  values (start_bulk.tenant, start_bulk.subject_type, start_bulk.action, coalesce(start_bulk.args, '{}'::jsonb), coalesce(start_bulk.ids, array[]::text[]), auth.uid())
  returning ${c("id")} into v_id;
  ${ctx.enqueue("bulk", "jsonb_build_object('run', v_id)", "'bulk:' || v_id::text")}
  return jsonb_build_object('id', v_id, 'total', v_total, 'topic', 'bulk:' || v_id::text);
end;
$$;
${userGrant(`${ctx.fn("start_bulk")}(${ctx.idType}, text, text[], text, jsonb)`)}

create or replace function ${ctx.fn("bulk_run")}(run_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.${c("id")}, 'organizationId', r.${c("tenant")}, 'subjectType', r.${c("subjectType")},
    'action', r.${c("action")}, 'status', r.${c("status")}, 'total', cardinality(r.${c("ids")}),
    'position', r.${c("position")}, 'succeeded', r.${c("succeeded")}, 'failed', r.${c("failed")},
    'results', r.${c("results")}, 'createdAt', r.${c("createdAt")}, 'finishedAt', r.${c("finishedAt")})
  from ${runs} r where r.${c("id")} = bulk_run.run_id;
$$;
${userGrant(`${ctx.fn("bulk_run")}(uuid)`)}

-- Runs the next rows of a background run as the user who started it, with
-- their claims and the authenticated role, so their permissions and policies apply.
create or replace function ${ctx.fn("bulk_step")}(run_id uuid, size integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run ${runs}%rowtype;
  v_role text := current_user;
  v_claims text := current_setting('request.jwt.claims', true);
  v_size integer := least(greatest(coalesce(bulk_step.size, ${String(DEFAULT_CHUNK)}), 1), ${String(limit)});
  v_chunk text[];
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
  v_allowed boolean;
  v_status text;
  v_done boolean;
begin
  select * into v_run from ${runs} r where r.${c("id")} = bulk_step.run_id for update;
  if not found then
    ${fail("BULK_RUN_NOT_FOUND", "bulk run not found", "P0002")}
  end if;
  if v_run.${c("status")} in ('completed', 'failed') then
    return jsonb_build_object('id', v_run.${c("id")}, 'status', v_run.${c("status")}, 'done', true);
  end if;
  v_chunk := v_run.${c("ids")}[v_run.${c("position")} + 1 : v_run.${c("position")} + v_size];
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_run.${c("createdBy")}, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  set local role authenticated;
  v_allowed := ${ctx.scope.can(`v_run.${c("tenant")}`, run)};
  if v_allowed then
    ${rowLoop(ctx, `v_run.${c("tenant")}`, `v_run.${c("subjectType")}`, `v_run.${c("action")}`, `v_run.${c("args")}`, "false")}
  end if;
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  v_done := not v_allowed or v_run.${c("position")} + cardinality(coalesce(v_chunk, array[]::text[])) >= cardinality(v_run.${c("ids")});
  v_status := case when not v_allowed then 'failed' when v_done then 'completed' else 'running' end;
  update ${runs} set
    ${c("position")} = case when v_allowed then ${c("position")} + cardinality(coalesce(v_chunk, array[]::text[])) else ${c("position")} end,
    ${c("succeeded")} = ${c("succeeded")} + v_ok,
    ${c("failed")} = ${c("failed")} + v_failed,
    ${c("results")} = ${c("results")} || v_results,
    ${c("status")} = v_status,
    ${c("finishedAt")} = case when v_done then now() else null end
  where ${c("id")} = v_run.${c("id")}
  returning * into v_run;
  ${ctx.broadcast(
    `'bulk:' || v_run.${c("id")}::text`,
    "'progress'",
    `jsonb_build_object('id', v_run.${c("id")}, 'status', v_status, 'position', v_run.${c("position")}, 'total', cardinality(v_run.${c("ids")}), 'succeeded', v_run.${c("succeeded")}, 'failed', v_run.${c("failed")})`,
  )}
  if v_done then
    ${ctx.record({
      type: "bulk_run.completed",
      payload: `jsonb_build_object('organizationId', v_run.${c("tenant")}, 'id', v_run.${c("id")}, 'kind', v_run.${c("action")}, 'status', v_status, 'count', cardinality(v_run.${c("ids")}), 'failed', v_run.${c("failed")})`,
      subject: `'bulk-runs/' || v_run.${c("id")}::text`,
      tenant: `v_run.${c("tenant")}`,
      audit: false,
    })}
  end if;
  return jsonb_build_object('id', v_run.${c("id")}, 'status', v_status, 'position', v_run.${c("position")}, 'total', cardinality(v_run.${c("ids")}), 'succeeded', v_run.${c("succeeded")}, 'failed', v_run.${c("failed")}, 'done', v_done);
end;
$$;
${serviceGrant(`${ctx.fn("bulk_step")}(uuid, integer)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "bulk_apply",
      args: ["{id}", "text", "text[]", "text", "jsonb", "boolean"],
      returns: "jsonb",
    },
    {
      name: "start_bulk",
      args: ["{id}", "text", "text[]", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "bulk_run", args: ["uuid"], returns: "jsonb" },
    { name: "bulk_step", args: ["uuid", "integer"], returns: "jsonb" },
  ];
}

export const BULK: BlockSqlDefinition = {
  name: "bulk",
  scopes: ["tenant"],
  title: "Bulk actions",
  description:
    "One action over many rows: up to a limit in one call with a result per row, and larger sets as a background run on the jobs queue that runs as the user who started it.",
  requires: ["tenant", "access"],
  integrates: [
    "jobs",
    "outbox",
    "tags",
    "state-machine",
    "relations",
    "trash",
    "collections",
  ],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
