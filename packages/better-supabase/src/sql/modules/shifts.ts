import type { ShiftsEvents } from "../../blocks/shifts/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";
import { shiftAssignmentFunctions } from "./shifts-assignments.ts";
import { shiftFunctions } from "./shifts-functions.ts";
import { shiftReportFunctions, timeEntriesTarget } from "./shifts-reports.ts";
import {
  ASSIGNMENT_STATUSES,
  AVAILABILITY_KINDS,
  minRestHours,
  qualificationCheck,
  SHIFT_RESERVED,
  SHIFT_STATUSES,
  shiftTimeZone,
  sqlList,
  SWAP_STATUSES,
  teamType,
} from "./shifts-shared.ts";

const SHIFT = [
  "organizationId",
  "shiftId",
  "teamId",
  "startsAt",
  "endsAt",
] as const;

const ASSIGNMENT = [
  "organizationId",
  "shiftId",
  "assignmentId",
  "userId",
  "startsAt",
  "endsAt",
] as const;

const SWAP = [
  "organizationId",
  "swapId",
  "assignmentId",
  "shiftId",
  "fromUserId",
  "toUserId",
] as const;

const EVENTS: BlockSqlEvents<ShiftsEvents> = {
  "shift.created": { subject: "shifts", payload: [...SHIFT, "status"] },
  "shift.published": { subject: "shifts", payload: SHIFT },
  "shift.cancelled": { subject: "shifts", payload: [...SHIFT, "reason"] },
  "shift_assignment.created": { subject: "shifts", payload: ASSIGNMENT },
  "shift_assignment.released": {
    subject: "shifts",
    payload: [...ASSIGNMENT, "reason"],
  },
  "shift_swap.requested": { subject: "shifts", payload: SWAP },
  "shift_swap.decided": { subject: "shifts", payload: [...SWAP, "status"] },
};

const NAMES: BlockSqlNames = {
  entities: {
    shift: { table: "shifts", singular: "shift", primary: true },
    shift_template: { table: "templates", singular: "shift_template" },
    shift_assignment: { table: "assignments", singular: "shift_assignment" },
    shift_swap: { table: "swaps", singular: "shift_swap" },
    shift_availability: {
      table: "availability",
      singular: "shift_availability",
      plural: "shift_availability",
    },
  },
  events: EVENTS,
  hooks: [
    "before_shift_save",
    "after_shift_save",
    "before_shift_cancel",
    "after_shift_cancel",
    "before_shift_assignment_create",
    "after_shift_assignment_create",
  ],
  options: ["minRestHours", "qualificationCheck", "timeZone", "extraColumns"],
  tables: {
    templates: {
      name: "shift_templates",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        team: "team_id",
        location: "location_id",
        startsTime: "starts_time",
        endsTime: "ends_time",
        breakMinutes: "break_minutes",
        headcount: "headcount",
        requiredQualifications: "required_qualifications",
        weekdays: "weekdays",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["location", "createdAt", "updatedAt"],
    },
    shifts: {
      name: "shifts",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        template: "template_id",
        team: "team_id",
        location: "location_id",
        startsAt: "starts_at",
        endsAt: "ends_at",
        breakMinutes: "break_minutes",
        headcount: "headcount",
        requiredQualifications: "required_qualifications",
        status: "status",
        note: "note",
        publishedAt: "published_at",
        canceledAt: "canceled_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["location", "note", "createdBy", "createdAt", "updatedAt"],
    },
    assignments: {
      name: "shift_assignments",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        shift: "shift_id",
        user: "user_id",
        status: "status",
        startsAt: "starts_at",
        endsAt: "ends_at",
        assignedBy: "assigned_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["assignedBy", "createdAt", "updatedAt"],
    },
    swaps: {
      name: "shift_swaps",
      app: {},
      lifecycle: { tenant: "tenant", user: "fromUser", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        assignment: "assignment_id",
        fromUser: "from_user_id",
        toUser: "to_user_id",
        status: "status",
        approval: "approval_id",
        note: "note",
        decidedBy: "decided_by",
        decidedAt: "decided_at",
        createdAt: "created_at",
      },
      optional: ["approval", "note", "decidedBy", "createdAt"],
    },
    availability: {
      name: "shift_availability",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        onDate: "on_date",
        fromTime: "from_time",
        untilTime: "until_time",
        kind: "kind",
        note: "note",
        createdAt: "created_at",
      },
      optional: ["note", "createdAt"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const templates = ctx.table("templates");
  const shifts = ctx.table("shifts");
  const assignments = ctx.table("assignments");
  const swaps = ctx.table("swaps");
  const availability = ctx.table("availability");
  const t = (column: string): string => ctx.col("templates", column);
  const s = (column: string): string => ctx.col("shifts", column);
  const a = (column: string): string => ctx.col("assignments", column);
  const w = (column: string): string => ctx.col("swaps", column);
  const v = (column: string): string => ctx.col("availability", column);
  const permissions = moduleOperations("shifts");
  const read = ctx.permission("read", permissions.read);
  const write = ctx.permission("write", permissions.write);
  const manage = ctx.permission("manage", permissions.manage);
  const extras = ctx.extraColumns("shifts", SHIFT_RESERVED);

  const teams = ctx.of("teams");
  const team = teamType(ctx);

  const assets =
    ctx.installed("assets") && ctx.of("assets").owns("assets")
      ? ctx.of("assets")
      : undefined;

  const approvals =
    ctx.installed("approvals") && ctx.of("approvals").owns("requests")
      ? ctx.of("approvals")
      : undefined;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const stamps = (logical: string, columns: readonly string[]): string =>
    columns
      .map((column) =>
        opt(
          logical,
          column,
          () =>
            `${ctx.col(logical, column)} timestamptz not null default now()`,
        ),
      )
      .join("");

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

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const ref = (
    other: BlockSqlContext | undefined,
    logical: string,
    action = "set null",
  ): string =>
    other === undefined
      ? ""
      : ` references ${other.table(logical)} (${other.col(logical, "id")}) on delete ${action}`;

  const teamRef = ctx.of("teams").owns("teams") ? ref(teams, "teams") : "";
  const assetRef = ref(assets, "assets");
  const approvalRef = ref(approvals, "requests");

  const locationIndex = (logical: string): string =>
    ctx.has(logical, "location")
      ? `\ncreate index if not exists ${name(logical, "location_idx")} on ${ctx.table(logical)} (${ctx.col(logical, "location")}) where ${ctx.col(logical, "location")} is not null;`
      : "";

  return `
create extension if not exists btree_gist with schema extensions;

create table if not exists ${templates} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${ctx.idType} not null,
  ${t("name")} text not null check (length(${t("name")}) between 1 and 200),
  ${t("team")} ${team}${teamRef},${opt("templates", "location", () => `${t("location")} uuid${assetRef}`)}
  -- An end at or before the start runs into the next day.
  ${t("startsTime")} time not null,
  ${t("endsTime")} time not null,
  ${t("breakMinutes")} integer not null default 0 check (${t("breakMinutes")} >= 0 and ${t("breakMinutes")} <= 720),
  ${t("headcount")} integer not null default 1 check (${t("headcount")} >= 1 and ${t("headcount")} <= 500),
  -- Qualification type keys (qualifications block) everyone on the shift holds.
  ${t("requiredQualifications")} text[] not null default '{}',
  -- ISO weekdays, 1 (Monday) to 7 (Sunday), generate_shifts creates shifts on.
  ${t("weekdays")} integer[] not null default '{1,2,3,4,5}' check (${t("weekdays")} <@ array[1, 2, 3, 4, 5, 6, 7]),
  ${t("archivedAt")} timestamptz,${stamps("templates", ["createdAt", "updatedAt"])}
  unique (${t("tenant")}, ${t("id")})
);${appKey("templates", "tenant_id", `${t("tenant")}, ${t("id")}`)}
create index if not exists ${name("templates", "tenant_idx")} on ${templates} (${t("tenant")}, ${t("name")});
create index if not exists ${name("templates", "team_idx")} on ${templates} (${t("team")}) where ${t("team")} is not null;${locationIndex("templates")}
${lockModuleTable(ctx, "templates", { read: true })}
${readPolicy("templates", ctx.scope.check(t("tenant"), read))}

create table if not exists ${shifts} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("template")} uuid,
  ${s("team")} ${team}${teamRef},${opt("shifts", "location", () => `${s("location")} uuid${assetRef}`)}
  ${s("startsAt")} timestamptz not null,
  ${s("endsAt")} timestamptz not null,
  ${s("breakMinutes")} integer not null default 0 check (${s("breakMinutes")} >= 0 and ${s("breakMinutes")} <= 720),
  ${s("headcount")} integer not null default 1 check (${s("headcount")} >= 1 and ${s("headcount")} <= 500),
  ${s("requiredQualifications")} text[] not null default '{}',
  -- draft: planners see it; published: everyone with shifts.read does.
  ${s("status")} text not null default 'draft' check (${s("status")} in ${sqlList(SHIFT_STATUSES)}),${opt("shifts", "note", () => `${s("note")} text check (${s("note")} is null or length(${s("note")}) <= 2000)`)}
  ${s("publishedAt")} timestamptz,
  ${s("canceledAt")} timestamptz,${opt("shifts", "createdBy", () => `${s("createdBy")} uuid`)}${stamps("shifts", ["createdAt", "updatedAt"])}
  check (${s("endsAt")} > ${s("startsAt")}),
  check (${s("endsAt")} - ${s("startsAt")} <= interval '24 hours'),
  unique (${s("tenant")}, ${s("id")}),
  foreign key (${s("tenant")}, ${s("template")}) references ${templates} (${t("tenant")}, ${t("id")}) on delete set null (${s("template")})
);${addExtraColumns(shifts, extras)}${appKey("shifts", "tenant_id", `${s("tenant")}, ${s("id")}`)}
create index if not exists ${name("shifts", "tenant_idx")} on ${shifts} (${s("tenant")}, ${s("startsAt")});
create index if not exists ${name("shifts", "template_idx")} on ${shifts} (${s("tenant")}, ${s("template")}) where ${s("template")} is not null;
create index if not exists ${name("shifts", "team_idx")} on ${shifts} (${s("team")}) where ${s("team")} is not null;${locationIndex("shifts")}
${lockModuleTable(ctx, "shifts", { read: true })}
${readPolicy("shifts", `${ctx.scope.check(s("tenant"), write)} or (${s("status")} <> 'draft' and ${ctx.scope.check(s("tenant"), read)})`)}

create table if not exists ${assignments} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("shift")} uuid not null,
  ${a("user")} uuid not null,
  -- requested: the member asked for an open shift; released: no longer on it.
  ${a("status")} text not null default 'assigned' check (${a("status")} in ${sqlList(ASSIGNMENT_STATUSES)}),
  -- The shift's times, copied so the exclusion constraint can read them.
  ${a("startsAt")} timestamptz not null,
  ${a("endsAt")} timestamptz not null,${opt("assignments", "assignedBy", () => `${a("assignedBy")} uuid`)}${stamps("assignments", ["createdAt", "updatedAt"])}
  unique (${a("shift")}, ${a("user")}),
  unique (${a("tenant")}, ${a("id")}),
  foreign key (${a("tenant")}, ${a("shift")}) references ${shifts} (${s("tenant")}, ${s("id")}) on delete cascade,
  constraint ${name("assignments", "no_overlap")} exclude using gist (
    ${a("tenant")} with =,
    ${a("user")} with =,
    tstzrange(${a("startsAt")}, ${a("endsAt")}) with &&
  ) where (${a("status")} = 'assigned')
);${appKey("assignments", "shift_user_key", `${a("shift")}, ${a("user")}`)}${appKey("assignments", "tenant_id", `${a("tenant")}, ${a("id")}`)}
create index if not exists ${name("assignments", "tenant_idx")} on ${assignments} (${a("tenant")}, ${a("shift")});
create index if not exists ${name("assignments", "user_idx")} on ${assignments} (${a("user")}, ${a("startsAt")});
${lockModuleTable(ctx, "assignments", { read: true })}
${readPolicy("assignments", `${a("user")} = (select auth.uid()) or ${ctx.scope.check(a("tenant"), read)}`)}

create table if not exists ${swaps} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  ${w("assignment")} uuid not null,
  ${w("fromUser")} uuid not null,
  ${w("toUser")} uuid not null,
  ${w("status")} text not null default 'pending' check (${w("status")} in ${sqlList(SWAP_STATUSES)}),${opt("swaps", "approval", () => `${w("approval")} uuid${approvalRef}`)}${opt("swaps", "note", () => `${w("note")} text check (${w("note")} is null or length(${w("note")}) <= 2000)`)}${opt("swaps", "decidedBy", () => `${w("decidedBy")} uuid`)}
  ${w("decidedAt")} timestamptz,${stamps("swaps", ["createdAt"])}
  check (${w("toUser")} <> ${w("fromUser")}),
  foreign key (${w("tenant")}, ${w("assignment")}) references ${assignments} (${a("tenant")}, ${a("id")}) on delete cascade
);
create index if not exists ${name("swaps", "tenant_idx")} on ${swaps} (${w("tenant")}, ${w("assignment")});
create unique index if not exists ${name("swaps", "pending_idx")} on ${swaps} (${w("assignment")}) where ${w("status")} = 'pending';
create index if not exists ${name("swaps", "to_user_idx")} on ${swaps} (${w("toUser")});${
    ctx.has("swaps", "approval") && approvalRef !== ""
      ? `\ncreate index if not exists ${name("swaps", "approval_idx")} on ${swaps} (${w("approval")}) where ${w("approval")} is not null;`
      : ""
  }
${lockModuleTable(ctx, "swaps", { read: true })}
${readPolicy("swaps", `${w("fromUser")} = (select auth.uid()) or ${w("toUser")} = (select auth.uid()) or ${ctx.scope.check(w("tenant"), manage)}`)}

create table if not exists ${availability} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${ctx.idType} not null,
  ${v("user")} uuid not null,
  ${v("onDate")} date not null,
  -- Both null: the whole day.
  ${v("fromTime")} time,
  ${v("untilTime")} time,
  ${v("kind")} text not null check (${v("kind")} in ${sqlList(AVAILABILITY_KINDS)}),${opt("availability", "note", () => `${v("note")} text check (${v("note")} is null or length(${v("note")}) <= 500)`)}${stamps("availability", ["createdAt"])}
  check ((${v("fromTime")} is null) = (${v("untilTime")} is null)),
  check (${v("untilTime")} is null or ${v("untilTime")} > ${v("fromTime")}),
  unique (${v("tenant")}, ${v("user")}, ${v("onDate")})
);${appKey("availability", "user_day_key", `${v("tenant")}, ${v("user")}, ${v("onDate")}`)}
create index if not exists ${name("availability", "day_idx")} on ${availability} (${v("tenant")}, ${v("onDate")});
${lockModuleTable(ctx, "availability", { read: true })}
${readPolicy("availability", `${v("user")} = (select auth.uid()) or ${ctx.scope.check(v("tenant"), write)}`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  minRestHours(ctx);
  qualificationCheck(ctx);
  shiftTimeZone(ctx);

  return `${schemaPreamble(ctx)}
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.
${tables(ctx)}${shiftFunctions(ctx)}${shiftAssignmentFunctions(ctx)}${shiftReportFunctions(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const team = teamType(ctx);

  const extra = extraFieldsArg(
    ctx.extraColumns("shifts", SHIFT_RESERVED),
  ).contract;

  const timeEntries: readonly BlockSqlContractFunction[] =
    timeEntriesTarget(ctx) === undefined
      ? []
      : [
          {
            name: "shifts_to_time_entries",
            args: ["{id}", "timestamptz"],
            returns: "integer",
          },
        ];

  return [
    {
      name: "save_shift_template",
      args: [
        "{id}",
        "text",
        "time",
        "time",
        "integer[]",
        team,
        "uuid",
        "integer",
        "integer",
        "text[]",
        "uuid",
      ],
      returns: "jsonb",
    },
    { name: "archive_shift_template", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_shift_templates",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "generate_shifts",
      args: ["{id}", "uuid", "date", "date"],
      returns: "jsonb",
    },
    {
      name: "save_shift",
      args: [
        "{id}",
        "timestamptz",
        "timestamptz",
        team,
        "uuid",
        "integer",
        "integer",
        "text[]",
        "text",
        "uuid",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "cancel_shift", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "publish_shifts",
      args: ["{id}", "date", "date", team],
      returns: "integer",
    },
    { name: "assign_shift", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "unassign_shift", args: ["uuid", "text"], returns: "jsonb" },
    { name: "request_open_shift", args: ["uuid"], returns: "jsonb" },
    {
      name: "decide_shift_request",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "request_shift_swap",
      args: ["uuid", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "decide_shift_swap",
      args: ["uuid", "boolean", "uuid"],
      returns: "jsonb",
    },
    {
      name: "set_shift_availability",
      args: ["{id}", "date", "text", "time", "time", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_shift_availability",
      args: ["{id}", "date", "date", "uuid"],
      returns: "jsonb",
    },
    { name: "roster", args: ["{id}", "date", "date", team], returns: "jsonb" },
    {
      name: "my_shifts",
      args: ["timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    { name: "shift_hours", args: ["{id}", "date"], returns: "jsonb" },
    ...timeEntries,
  ];
}

export const SHIFTS: BlockSqlDefinition = {
  name: "shifts",
  scopes: ["tenant"],
  title: "Shifts",
  description:
    "Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.",
  requires: ["memberships", "permissions", "teams"],
  integrates: [
    "employees",
    "leave",
    "qualifications",
    "time-tracking",
    "assets",
    "approvals",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  internal: ["shift_assignment_check"],
};
