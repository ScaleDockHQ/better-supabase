import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { ActivitySourceName } from "./timeline-reads.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { SERVICE_CALLER, schemaPreamble, pageSize, fail } from "../shared.ts";
import { tableMoves } from "../table-renames.ts";
import { storedTypesData } from "./event-type-renames.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";
import { activityReads } from "./timeline-reads.ts";

const NAMES: BlockSqlNames = {
  migrations: tableMoves("timeline", 1),
  entities: {
    timeline_entry: {
      table: "activity",
      singular: "timeline_entry",
      formerly: "activity_entry",
      primary: true,
    },
  },
  tables: {
    activity: {
      name: "timeline_entries",
      app: {},
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        event: "event_id",
        type: "type",
        actor: "actor_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        summary: "summary",
        data: "data",
        occurredAt: "occurred_at",
      },
      optional: ["actor", "summary"],
    },
  },
};

const SOURCE_COMMENTS: Readonly<Record<ActivitySourceName, string>> = {
  event: "event for an activity entry",
  audit: "audit for an audit log entry on the subject's row",
  delivery: "delivery for a notification delivery about the subject",
  run: "run for a workflow run on the subject",
  transition: "transition for a state-machine status change of the subject",
  message: "message for a message in the subject's conversation",
};

function sourcesComment(sources: readonly ActivitySourceName[]): string {
  return sources.map((source) => SOURCE_COMMENTS[source]).join(",\n-- ");
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const activity = ctx.table("activity");
  const a = (logical: string): string => ctx.col("activity", logical);
  const fn = (name: string): string => ctx.fn(name);
  const reads = activityReads(ctx);

  const readCall = ctx.read(
    "list_activity.subject_type",
    "list_activity.subject_id",
    "list_activity",
  );

  const logRead =
    readCall === ""
      ? ""
      : `
  if list_activity.subject_id is not null and jsonb_array_length(v_rows) > 0 then
    ${readCall}
  end if;`;

  const read = ctx.permission("read", moduleOperations("timeline").read);

  // A column definition, left out when the app maps the column to null.
  const column = (
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has("activity", logical) ? `\n  ${definition(a(logical))},` : "";

  const written = [
    "event",
    "tenant",
    "type",
    "actor",
    "subjectType",
    "subjectId",
    "summary",
    "data",
    "occurredAt",
  ].filter((logical) => ctx.has("activity", logical));

  const values: Readonly<Record<string, string>> = {
    event: "e ->> 'event_id'",
    tenant: `(e ->> 'organization_id')::${id}`,
    type: "e ->> 'type'",
    actor: "nullif(e ->> 'actor_id', '')::uuid",
    subjectType: "e ->> 'subject_type'",
    subjectId: "e ->> 'subject_id'",
    summary: "e ->> 'summary'",
    data: "coalesce(e -> 'data', '{}'::jsonb)",
    occurredAt: "coalesce((e ->> 'occurred_at')::timestamptz, now())",
  };

  // The select list, broken where the default render breaks it.
  const selected = [
    ["event", "tenant", "type", "actor"],
    ["subjectType", "subjectId", "summary", "data"],
    ["occurredAt"],
  ]
    .map((group) =>
      group
        .filter((logical) => ctx.has("activity", logical))
        .map((logical) => values[logical])
        .join(", "),
    )
    .filter((line) => line !== "")
    .join(",\n    ");

  return `${schemaPreamble(ctx)}
-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists ${activity} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.scope.column()},
  ${a("event")} text not null unique,
  ${a("type")} text not null,${column("actor", (name) => `${name} uuid references auth.users (id) on delete set null`)}
  ${a("subjectType")} text,
  ${a("subjectId")} text,${column("summary", (name) => `${name} text`)}
  ${a("data")} jsonb not null default '{}'::jsonb,
  ${a("occurredAt")} timestamptz not null default now()
);${appUniqueIndex(ctx, "activity", ["event"])}
create index if not exists ${sqlIdent(`${ctx.tableName("activity").name}_feed_idx`)} on ${activity} (${a("tenant")}, ${a("occurredAt")} desc, ${a("id")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("activity").name}_subject_idx`)} on ${activity} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")});
${ctx.has("activity", "actor") ? `create index if not exists ${sqlIdent(`${ctx.tableName("activity").name}_actor_idx`)} on ${activity} (${a("actor")});\n` : ""}${lockModuleTable(ctx, "activity", { read: true })}
${reads.readable}${renderPolicy(makePolicy({ table: activity, name: sqlIdent(`${ctx.tableName("activity").name}_read`), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(a("tenant"), read)}${reads.rowCheck}` }), { drop: true, target: activity })}${reads.dropReadable}${reads.helpers}

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function ${fn("record_activity")}(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("TIMELINE_ENTRY_FORBIDDEN", "Only the service role records activity")}
  end if;
  insert into ${activity} (${written.map((logical) => a(logical)).join(", ")})
  select ${selected}
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict (${a("event")}) do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: ${sourcesComment(reads.sources)}.${reads.gate === "" ? "" : "\n-- A registered subject's timeline is empty unless can_subject grants read."}
create or replace function ${fn("list_activity")}(
  tenant ${id},
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
${ctx.readVolatility()}
security invoker
set search_path = ''
as $$
declare
  v_limit integer := ${pageSize("list_activity.max_rows", 50, 500)};
  v_rows jsonb;${reads.auditBranch === "" ? "" : "\n  v_table text;"}
begin${reads.gate}${reads.auditSetup}
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y.${a("occurredAt")} as at, y.${a("id")}::text as id
    from ${activity} y
    where ${ctx.scope.eq(`y.${a("tenant")}`, ctx.scope.value("list_activity.tenant"))}
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y.${a("subjectType")} = list_activity.subject_type)
      and (list_activity.subject_id is null or y.${a("subjectId")} = list_activity.subject_id)
      and (list_activity.before is null or y.${a("occurredAt")} < list_activity.before)${reads.eventDedupe}
    order by y.${a("occurredAt")} desc, y.${a("id")} desc
    limit v_limit)${reads.auditBranch}${reads.sourceBranches}
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;${logRead}
  return v_rows;
end;
$$;
revoke execute on function ${fn("list_activity")}(${id}, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function ${fn("record_activity")}(jsonb) from public, anon, authenticated;
grant execute on function ${fn("list_activity")}(${id}, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function ${fn("record_activity")}(jsonb) to service_role;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "list_activity",
      args: [
        "{id}",
        "text",
        "text",
        "timestamp with time zone",
        "integer",
        "text[]",
      ],
      returns: "jsonb",
    },
    { name: "record_activity", args: ["jsonb"], returns: "integer" },
  ];
}

export const ACTIVITY: BlockSqlDefinition = {
  internal: ["activity_subject_readable", "activity_subject_deliveries"],
  name: "timeline",
  scopes: ["tenant", "user", "none"],
  title: "Activity feed",
  description:
    "A timeline_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.",
  requires: ["memberships", "permissions"],
  integrates: [
    "notifications",
    "subjects",
    "audit",
    "workflows",
    "state-machine",
    "messaging",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  names: NAMES,
  data: (ctx) => storedTypesData(ctx, [["activity", "type"]]),
  contract,
  build,
};
