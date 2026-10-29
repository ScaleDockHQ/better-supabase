import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, serviceGrant } from "../shared.ts";

interface Recorded {
  readonly logical: string;
  readonly arg: string;
  readonly cast?: (value: string) => string;
}

/**
 * Whether the runs table keeps who a run's steps act as. An adopted table may
 * leave both principal columns out; the run then reports the principal from its
 * `bsb.principal_kind` and `bsb.principal` attributes.
 */
function principalColumns(ctx: BlockSqlContext): boolean {
  return ctx.has("runs", "principalKind") && ctx.has("runs", "principalId");
}

export const WORKFLOW_RUN_STATUSES = [
  "queued",
  "running",
  "waiting",
  "completed",
  "failed",
  "cancelled",
] as const;

/** Who a run's steps act as: `principal_kind` on `workflow_runs`. */
const PRINCIPAL_KINDS = [
  "user",
  "service_principal",
  "system",
  "external",
] as const;

/** The principal column statements of the runs table, empty without them. */
export function principalColumnsSql(ctx: BlockSqlContext): string {
  if (!principalColumns(ctx)) {
    return "";
  }

  const r = ctx.table("runs");
  const kind = ctx.col("runs", "principalKind");
  const id = ctx.col("runs", "principalId");

  return `alter table ${r} add column if not exists ${kind} text check (${kind} in (${PRINCIPAL_KINDS.map(sqlString).join(", ")}));
alter table ${r} add column if not exists ${id} text check (length(${id}) between 1 and 200);`;
}

/** The `principalKind` and `principalId` pairs of a run's JSON. */
export function principalJson(ctx: BlockSqlContext, alias: string): string {
  const cr = (column: string): string => `${alias}.${ctx.col("runs", column)}`;

  return principalColumns(ctx)
    ? `'principalKind', ${cr("principalKind")},
    'principalId', ${cr("principalId")}`
    : `'principalKind', ${cr("attributes")} ->> 'bsb.principal_kind',
    'principalId', ${cr("attributes")} ->> 'bsb.principal'`;
}

/**
 * The record_workflow_run function of the workflows block: creates or updates
 * the run an engine reports.
 */
export function recordWorkflowRunSql(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const r = ctx.table("runs");
  const cr = (column: string): string => ctx.col("runs", column);
  const linked = ctx.has("runs", "subjectType") && ctx.has("runs", "subjectId");
  const principaled = principalColumns(ctx);
  const moded = ctx.has("runs", "mode");
  const nodded = ctx.has("runs", "triggerNode");
  const app = ctx.appOwned.includes("runs");

  const recorded: readonly Recorded[] = [
    { logical: "engine", arg: "engine" },
    { logical: "externalId", arg: "external_id" },
    { logical: "definition", arg: "definition" },
    {
      logical: "status",
      arg: "status",
      cast: (value) => ctx.cast("runs", "status", value),
    },
    { logical: "tenant", arg: "tenant" },
    { logical: "actor", arg: "actor" },
    { logical: "attributes", arg: "coalesce(attributes, '{}'::jsonb)" },
    { logical: "error", arg: "left(error, 4000)" },
    { logical: "startedAt", arg: "started_at" },
    { logical: "completedAt", arg: "completed_at" },
    ...(linked
      ? [
          { logical: "subjectType", arg: "subject_type" },
          { logical: "subjectId", arg: "subject_id" },
        ]
      : []),
    ...(principaled
      ? [
          { logical: "principalKind", arg: "principal_kind" },
          { logical: "principalId", arg: "principal_id" },
        ]
      : []),
    ...(moded
      ? [
          {
            logical: "mode",
            arg: "coalesce(mode, 'live')",
            cast: (value: string) => ctx.cast("runs", "mode", value),
          },
        ]
      : []),
    ...(nodded ? [{ logical: "triggerNode", arg: "trigger_node" }] : []),
  ];

  // On the app's table the upsert runs through execute: its conflict target
  // names the app's columns, which a parameter of the same name would replace.
  const value = (entry: Recorded, index: number): string => {
    const arg = app ? `$${index + 1}` : entry.arg;

    return entry.cast === undefined ? arg : entry.cast(arg);
  };

  return `-- Creates or updates the run an engine reports. tenant, actor, the subject,
-- the principal, the trigger node and started_at keep their first non-null
-- value, mode keeps the first report's (default live); attributes merge.
drop function if exists ${fn("record_workflow_run")}(text, text, text, text, ${id}, uuid, jsonb, text, timestamptz, timestamptz);
create or replace function ${fn("record_workflow_run")}(
  engine text,
  external_id text,
  definition text,
  status text,
  tenant ${id} default null,
  actor uuid default null,
  attributes jsonb default '{}'::jsonb,
  error text default null,
  started_at timestamptz default null,
  completed_at timestamptz default null,
  subject_type text default null,
  subject_id text default null,
  principal_kind text default null,
  principal_id text default null,
  mode text default null,
  trigger_node text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
begin${
    linked
      ? ""
      : `
  if subject_type is not null or subject_id is not null then
    ${fail("WORKFLOW_SUBJECT_UNSUPPORTED", "this workflow runs table has no subject columns", "22023")}
  end if;`
  }${
    moded
      ? ""
      : `
  if coalesce(mode, 'live') <> 'live' then
    ${fail("WORKFLOW_MODE_UNSUPPORTED", "this workflow runs table has no mode column, so every run is live", "22023")}
  end if;`
  }
  ${app ? "execute $q$" : ""}insert into ${r} as x (${recorded.map((entry) => cr(entry.logical)).join(", ")})
  values (${recorded.map(value).join(", ")})
  on conflict ${app ? `(${cr("engine")}, ${cr("externalId")})` : "on constraint workflow_runs_engine_external_key"} do update set
    ${cr("definition")} = excluded.${cr("definition")},
    ${cr("status")} = excluded.${cr("status")},
    ${cr("tenant")} = coalesce(x.${cr("tenant")}, excluded.${cr("tenant")}),
    ${cr("actor")} = coalesce(x.${cr("actor")}, excluded.${cr("actor")}),
    ${cr("attributes")} = x.${cr("attributes")} || excluded.${cr("attributes")},
    ${cr("error")} = coalesce(excluded.${cr("error")}, x.${cr("error")}),
    ${cr("startedAt")} = coalesce(x.${cr("startedAt")}, excluded.${cr("startedAt")}),
    ${cr("completedAt")} = coalesce(excluded.${cr("completedAt")}, x.${cr("completedAt")}),${
      linked
        ? `
    ${cr("subjectType")} = case when x.${cr("subjectType")} is null then excluded.${cr("subjectType")} else x.${cr("subjectType")} end,
    ${cr("subjectId")} = case when x.${cr("subjectType")} is null then excluded.${cr("subjectId")} else x.${cr("subjectId")} end,`
        : ""
    }${
      principaled
        ? `
    ${cr("principalKind")} = case when x.${cr("principalKind")} is null then excluded.${cr("principalKind")} else x.${cr("principalKind")} end,
    ${cr("principalId")} = case when x.${cr("principalKind")} is null then excluded.${cr("principalId")} else x.${cr("principalId")} end,`
        : ""
    }${nodded ? `\n    ${cr("triggerNode")} = coalesce(x.${cr("triggerNode")}, excluded.${cr("triggerNode")}),` : ""}
    ${cr("updatedAt")} = now()
  returning x.${cr("id")}${
    app
      ? `$q$
  into v_id
  using ${recorded.map((entry) => entry.arg).join(", ")};`
      : " into v_id;"
  }
  return v_id;
end;
$$;
${serviceGrant(`${fn("record_workflow_run")}(text, text, text, text, ${id}, uuid, jsonb, text, timestamptz, timestamptz, text, text, text, text, text, text)`)}`;
}
