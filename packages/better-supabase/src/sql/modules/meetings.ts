import type { MeetingsEvents } from "../../blocks/meetings/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { meetingFunctions } from "./meetings-functions.ts";
import { meetingIntegrations } from "./meetings-integrations.ts";
import { meetingReads } from "./meetings-read.ts";
import { meetingsSql } from "./meetings-sql.ts";
import {
  MEETING_AGENDA_STATUSES,
  MEETING_ATTENDANCE,
  MEETING_ATTENDEE_ROLES,
  MEETING_DECISION_STATUSES,
  MEETING_STATUSES,
} from "./meetings-values.ts";

const MEETING = ["organizationId", "id", "kind", "title", "status"] as const;

const meeting = { subject: "meetings", payload: MEETING } as const;

const DECISION = [
  "organizationId",
  "id",
  "meetingId",
  "title",
  "status",
] as const;

const decision = { subject: "meeting-decisions", payload: DECISION } as const;

const EVENTS: BlockSqlEvents<MeetingsEvents> = {
  "meeting.created": meeting,
  "meeting.updated": meeting,
  "meeting.started": meeting,
  "meeting.concluded": meeting,
  "meeting.cancelled": { subject: "meetings", payload: [...MEETING, "reason"] },
  "meeting.deleted": meeting,
  "meeting_decision.recorded": decision,
  "meeting_decision.decided": decision,
  "meeting_action_item.created": {
    subject: "meetings",
    payload: ["organizationId", "meetingId", "workItemId", "title"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    meeting: {
      table: "meetings",
      singular: "meeting",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["location", "summary"] },
      },
    },
    meeting_attendee: { table: "attendees", singular: "meeting_attendee" },
    meeting_agenda_item: { table: "agenda", singular: "meeting_agenda_item" },
    meeting_decision: {
      table: "decisions",
      singular: "meeting_decision",
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    meeting_action_item: { table: "actions", singular: "meeting_action_item" },
  },
  events: EVENTS,
  hooks: [
    "before_meeting_create",
    "after_meeting_create",
    "before_meeting_hold",
    "after_meeting_hold",
    "after_meeting_decision",
  ],
  options: ["kinds", "calendar", "extraColumns"],
  tables: {
    meetings: {
      name: "meetings",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        title: "title",
        location: "location",
        startsAt: "starts_at",
        endsAt: "ends_at",
        status: "status",
        startedAt: "started_at",
        heldAt: "held_at",
        summary: "summary",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["location", "summary", "createdBy"],
    },
    attendees: {
      name: "meeting_attendees",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        meeting: "meeting_id",
        tenant: "tenant_id",
        user: "user_id",
        role: "role",
        attendance: "attendance",
        createdAt: "created_at",
      },
    },
    agenda: {
      name: "meeting_agenda_items",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        meeting: "meeting_id",
        ordinal: "ordinal",
        title: "title",
        notes: "notes",
        presenter: "presenter_id",
        minutes: "minutes",
        status: "status",
        outcome: "outcome",
        createdAt: "created_at",
      },
      optional: ["notes", "outcome"],
    },
    decisions: {
      name: "meeting_decisions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        meeting: "meeting_id",
        agendaItem: "agenda_item_id",
        title: "title",
        body: "body",
        status: "status",
        decidedBy: "decided_by",
        decidedAt: "decided_at",
        createdAt: "created_at",
      },
      optional: ["body"],
    },
    actions: {
      name: "meeting_action_items",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        task: "task_id",
        tenant: "tenant_id",
        meeting: "meeting_id",
        agendaItem: "agenda_item_id",
        decision: "decision_id",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = meetingsSql(ctx);

  const { m, a, g, d, x, fn, meetings, attendees, agenda, decisions, actions } =
    q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, using: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using,
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const text = (column: string, max: number): string =>
    `${column} text check (${column} is null or length(${column}) <= ${String(max)})`;

  const tasks = ctx.of("tasks");

  const taskRef = tasks.owns("items")
    ? ` references ${tasks.table("items")} (${tasks.col("items", "id")}) on delete cascade`
    : "";

  const reads = (tenant: string, meeting: string): string =>
    `(${ctx.scope.check(tenant, q.read)}) or ${fn("meeting_role")}(${meeting}) is not null`;

  return `
create table if not exists ${meetings} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  -- One of options.kinds; the functions check it.
  ${m("kind")} text not null check (length(${m("kind")}) between 1 and 63),
  ${m("title")} text not null check (length(${m("title")}) between 1 and 300),${opt("meetings", "location", () => text(m("location"), 500))}
  ${m("startsAt")} timestamptz not null,
  ${m("endsAt")} timestamptz,
  ${m("status")} text not null default 'planned' check (${m("status")} in (${list(MEETING_STATUSES)})),
  ${m("startedAt")} timestamptz,
  ${m("heldAt")} timestamptz,${opt("meetings", "summary", () => text(m("summary"), 20_000))}${opt("meetings", "createdBy", () => `${m("createdBy")} uuid`)}
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("id")}),
  check (${m("endsAt")} is null or ${m("endsAt")} >= ${m("startsAt")})
);${addExtraColumns(meetings, q.extras)}${appKey("meetings", "tenant_id", `${m("tenant")}, ${m("id")}`)}
create index if not exists ${name("meetings", "tenant_idx")} on ${meetings} (${m("tenant")}, ${m("status")}, ${m("startsAt")} desc);
${lockTable(meetings, { read: true })}

create table if not exists ${attendees} (
  ${a("meeting")} uuid not null,
  ${a("tenant")} ${ctx.idType} not null,
  ${a("user")} uuid not null,
  ${a("role")} text not null default 'attendee' check (${a("role")} in (${list(MEETING_ATTENDEE_ROLES)})),
  ${a("attendance")} text not null default 'invited' check (${a("attendance")} in (${list(MEETING_ATTENDANCE)})),
  ${a("createdAt")} timestamptz not null default now(),
  primary key (${a("meeting")}, ${a("user")}),
  foreign key (${a("tenant")}, ${a("meeting")}) references ${meetings} (${m("tenant")}, ${m("id")}) on delete cascade
);${appKey("attendees", "meeting_user", `${a("meeting")}, ${a("user")}`)}
create index if not exists ${name("attendees", "parent_idx")} on ${attendees} (${a("tenant")}, ${a("meeting")});
create index if not exists ${name("attendees", "user_idx")} on ${attendees} (${a("user")}, ${a("meeting")});
-- One chair per meeting.
create unique index if not exists ${name("attendees", "chair_key")} on ${attendees} (${a("meeting")}) where ${a("role")} = 'chair';
${lockTable(attendees, { read: true })}

-- The caller's role at a meeting, or null. Definer, so the read policies can
-- ask it without reading the attendees table through its own policy.
create or replace function ${fn("meeting_role")}(meeting_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x.${a("role")} from ${attendees} x
  where x.${a("meeting")} = meeting_role.meeting_id and x.${a("user")} = auth.uid();
$$;
${userGrant(`${fn("meeting_role")}(uuid)`)}
${readPolicy("meetings", reads(m("tenant"), m("id")))}
${readPolicy("attendees", reads(a("tenant"), a("meeting")))}

create table if not exists ${agenda} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null,
  ${g("meeting")} uuid not null,
  ${g("ordinal")} integer not null check (${g("ordinal")} > 0),
  ${g("title")} text not null check (length(${g("title")}) between 1 and 300),${opt("agenda", "notes", () => text(g("notes"), 10_000))}
  ${g("presenter")} uuid,
  -- Minutes of this item, in Markdown.
  ${g("minutes")} text check (${g("minutes")} is null or length(${g("minutes")}) <= 50000),
  ${g("status")} text not null default 'open' check (${g("status")} in (${list(MEETING_AGENDA_STATUSES)})),${opt("agenda", "outcome", () => text(g("outcome"), 2000))}
  ${g("createdAt")} timestamptz not null default now(),
  unique (${g("tenant")}, ${g("id")}),
  unique (${g("meeting")}, ${g("ordinal")}) deferrable initially deferred,
  foreign key (${g("tenant")}, ${g("meeting")}) references ${meetings} (${m("tenant")}, ${m("id")}) on delete cascade
);${appKey("agenda", "meeting_ordinal", `${g("meeting")}, ${g("ordinal")}`)}${appKey("agenda", "tenant_id", `${g("tenant")}, ${g("id")}`)}
create index if not exists ${name("agenda", "parent_idx")} on ${agenda} (${g("tenant")}, ${g("meeting")}, ${g("ordinal")});
${lockTable(agenda, { read: true })}
${readPolicy("agenda", reads(g("tenant"), g("meeting")))}

create table if not exists ${decisions} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${ctx.idType} not null,
  ${d("meeting")} uuid not null,
  ${d("agendaItem")} uuid,
  ${d("title")} text not null check (length(${d("title")}) between 1 and 300),${opt("decisions", "body", () => text(d("body"), 10_000))}
  ${d("status")} text not null default 'proposed' check (${d("status")} in (${list(MEETING_DECISION_STATUSES)})),
  ${d("decidedBy")} uuid,
  ${d("decidedAt")} timestamptz,
  ${d("createdAt")} timestamptz not null default now(),
  unique (${d("tenant")}, ${d("id")}),
  foreign key (${d("tenant")}, ${d("meeting")}) references ${meetings} (${m("tenant")}, ${m("id")}) on delete cascade,
  foreign key (${d("tenant")}, ${d("agendaItem")}) references ${agenda} (${g("tenant")}, ${g("id")}) on delete set null (${d("agendaItem")})
);${appKey("decisions", "tenant_id", `${d("tenant")}, ${d("id")}`)}
create index if not exists ${name("decisions", "parent_idx")} on ${decisions} (${d("tenant")}, ${d("meeting")});
create index if not exists ${name("decisions", "agenda_idx")} on ${decisions} (${d("tenant")}, ${d("agendaItem")});
${lockTable(decisions, { read: true })}
${readPolicy("decisions", reads(d("tenant"), d("meeting")))}

-- The tasks opened from a meeting. The work item stays in the tasks block;
-- this row only says where it came from.
create table if not exists ${actions} (
  ${x("task")} uuid primary key${taskRef},
  ${x("tenant")} ${ctx.idType} not null,
  ${x("meeting")} uuid not null,
  ${x("agendaItem")} uuid,
  ${x("decision")} uuid,
  ${x("createdAt")} timestamptz not null default now(),
  foreign key (${x("tenant")}, ${x("meeting")}) references ${meetings} (${m("tenant")}, ${m("id")}) on delete cascade,
  foreign key (${x("tenant")}, ${x("agendaItem")}) references ${agenda} (${g("tenant")}, ${g("id")}) on delete set null (${x("agendaItem")}),
  foreign key (${x("tenant")}, ${x("decision")}) references ${decisions} (${d("tenant")}, ${d("id")}) on delete set null (${x("decision")})
);
create index if not exists ${name("actions", "parent_idx")} on ${actions} (${x("tenant")}, ${x("meeting")});
create index if not exists ${name("actions", "agenda_idx")} on ${actions} (${x("tenant")}, ${x("agendaItem")});
create index if not exists ${name("actions", "decision_idx")} on ${actions} (${x("tenant")}, ${x("decision")});
${lockTable(actions, { read: true })}
${readPolicy("actions", reads(x("tenant"), x("meeting")))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("tasks").mode === "custom") {
    throw new TypeError(
      "blocks.meetings needs the tasks tables for its action items; tasks can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- Meetings per organization: an agenda, attendees, minutes, decisions that
-- members vote on, and action items that become tasks.
${tables(ctx)}
${meetingFunctions(ctx)}
${meetingReads(ctx)}
${meetingIntegrations(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_meeting", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_meeting", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "start_meeting", args: ["uuid"], returns: "jsonb" },
    { name: "hold_meeting", args: ["uuid", "text"], returns: "jsonb" },
    { name: "cancel_meeting", args: ["uuid", "text"], returns: "jsonb" },
    { name: "delete_meeting", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_meeting_attendee",
      args: ["uuid", "uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "remove_meeting_attendee",
      args: ["uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "save_meeting_agenda_item",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "delete_meeting_agenda_item", args: ["uuid"], returns: "jsonb" },
    {
      name: "record_meeting_decision",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "decide_meeting_decision",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "add_meeting_action_item",
      args: ["uuid", "jsonb", "uuid[]", "uuid", "uuid"],
      returns: "jsonb",
    },
    { name: "get_meeting", args: ["uuid"], returns: "jsonb" },
    { name: "list_meetings", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

export const MEETINGS: BlockSqlDefinition = {
  name: "meetings",
  scopes: ["tenant"],
  title: "Meetings",
  description:
    "Meetings with an agenda, attendees and roles, minutes per agenda item, decisions the attendees vote on, and action items that become tasks.",
  requires: ["memberships", "permissions", "subjects", "tasks"],
  integrates: [
    "reactions",
    "documents",
    "calendar",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
