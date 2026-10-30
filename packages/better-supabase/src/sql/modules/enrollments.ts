import type { EnrollmentsEvents } from "../../blocks/enrollments/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { enrollmentsFunctions } from "./enrollments-functions.ts";
import { schedulesSteps } from "./enrollments-schedule.ts";
import { moduleOperations } from "./permissions-model.ts";

const PROGRAM_PAYLOAD = ["organizationId", "id", "key", "version"] as const;

const ENROLLMENT_PAYLOAD = [
  "organizationId",
  "id",
  "program",
  "subjectType",
  "subjectId",
  "status",
  "step",
  "completedSteps",
  "totalSteps",
] as const;

const EVENTS: BlockSqlEvents<EnrollmentsEvents> = {
  "enrollment_program.created": {
    subject: "enrollment-programs",
    payload: PROGRAM_PAYLOAD,
  },
  "enrollment_program.updated": {
    subject: "enrollment-programs",
    payload: PROGRAM_PAYLOAD,
  },
  "enrollment_program.deleted": {
    subject: "enrollment-programs",
    payload: PROGRAM_PAYLOAD,
  },
  "enrollment.created": { subject: "enrollments", payload: ENROLLMENT_PAYLOAD },
  "enrollment.step_completed": {
    subject: "enrollments",
    payload: ENROLLMENT_PAYLOAD,
  },
  "enrollment.completed": {
    subject: "enrollments",
    payload: ENROLLMENT_PAYLOAD,
  },
  "enrollment.cancelled": {
    subject: "enrollments",
    payload: ENROLLMENT_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    enrollment_program: {
      table: "programs",
      singular: "enrollment_program",
      primary: true,
    },
    enrollment: { table: "enrollments", singular: "enrollment" },
  },
  events: EVENTS,
  options: ["maxSteps"],
  tables: {
    programs: {
      name: "enrollment_programs",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      optional: ["description", "createdBy", "createdAt", "updatedAt"],
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        description: "description",
        subjectTypes: "subject_types",
        steps: "steps",
        enabled: "enabled",
        version: "version",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    enrollments: {
      name: "enrollments",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optional: ["programVersion", "startsAt", "endsAt"],
      typed: ["status"],
      columns: {
        id: "id",
        tenant: "tenant_id",
        program: "program",
        programVersion: "program_version",
        subjectType: "subject_type",
        subjectId: "subject_id",
        user: "user_id",
        steps: "steps",
        completedSteps: "completed_steps",
        status: "status",
        enrolledBy: "enrolled_by",
        enrolledAt: "enrolled_at",
        startsAt: "starts_at",
        endsAt: "ends_at",
        completedAt: "completed_at",
        cancelledAt: "cancelled_at",
        updatedAt: "updated_at",
      },
    },
    steps: {
      name: "enrollment_steps",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      optional: ["assigneeRole", "assigneeUser", "dueAt"],
      columns: {
        enrollment: "enrollment_id",
        tenant: "tenant_id",
        step: "step",
        assigneeRole: "assignee_role",
        assigneeUser: "assignee_user_id",
        dueAt: "due_at",
        completedBy: "completed_by",
        completedAt: "completed_at",
      },
    },
  },
};

function scheduleIndexes(
  ctx: BlockSqlContext,
  name: (logical: string, suffix: string) => string,
): string {
  if (!schedulesSteps(ctx)) {
    return "";
  }

  const steps = ctx.table("steps");
  const s = (column: string): string => ctx.col("steps", column);

  return `
create index if not exists ${name("steps", "assignee_idx")} on ${steps} (${s("assigneeUser")}, ${s("dueAt")});
create index if not exists ${name("steps", "due_idx")} on ${steps} (${s("tenant")}, ${s("dueAt")}) where ${s("completedAt")} is null;`;
}

/**
 * The enrollments tables, their indexes and read policies. The onboarding
 * upgrade writes them too, so its rows can move before this module renders.
 */
export function enrollmentTables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const programs = ctx.table("programs");
  const enrollments = ctx.table("enrollments");
  const steps = ctx.table("steps");
  const p = (column: string): string => ctx.col("programs", column);
  const e = (column: string): string => ctx.col("enrollments", column);
  const s = (column: string): string => ctx.col("steps", column);
  const read = ctx.permission("read", moduleOperations("enrollments").read);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const optional = (
    table: string,
    column: string,
    definition: (ident: string) => string,
  ): string =>
    ctx.has(table, column) ? `\n  ${definition(ctx.col(table, column))},` : "";

  // Over the app's table the render drops the inline keys the upserts rely on.
  const key = (logical: string, suffix: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${suffix}`)} on ${ctx.table(logical)} ${columns};`;

  return `create table if not exists ${programs} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("key")} text not null check (${p("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),${optional("programs", "description", (c) => `${c} text check (${c} is null or length(${c}) <= 2000)`)}
  -- The subject types it enrolls; empty enrolls any.
  ${p("subjectTypes")} text[] not null default '{}',
  -- [{ id, title, description }], in order.
  ${p("steps")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${p("steps")}) = 'array'),
  ${p("enabled")} boolean not null default true,
  ${p("version")} integer not null default 1,${optional("programs", "createdBy", (c) => `${c} uuid`)}${optional("programs", "createdAt", (c) => `${c} timestamptz not null default now()`)}${optional("programs", "updatedAt", (c) => `${c} timestamptz not null default now()`)}
  unique (${p("tenant")}, ${p("key")})
);${key("programs", "key_key", `(${p("tenant")}, ${p("key")})`)}

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists ${enrollments} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType},
  ${e("program")} text not null check (length(${e("program")}) between 1 and 200),${optional("enrollments", "programVersion", (c) => `${c} integer`)}
  ${e("subjectType")} text not null check (${e("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${e("subjectId")} text not null check (length(${e("subjectId")}) between 1 and 200),
  ${e("user")} uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  ${e("steps")} text[] not null default '{}',
  ${e("completedSteps")} integer not null default 0 check (${e("completedSteps")} >= 0),
  ${e("status")} text not null default 'active' check (${e("status")} in ('active', 'completed', 'cancelled')),
  ${e("enrolledBy")} uuid,
  ${e("enrolledAt")} timestamptz not null default now(),${optional("enrollments", "startsAt", (c) => `${c} timestamptz`)}${optional("enrollments", "endsAt", (c) => `${c} timestamptz`)}
  ${e("completedAt")} timestamptz,
  ${e("cancelledAt")} timestamptz,
  ${e("updatedAt")} timestamptz not null default now(),
  check ((${e("subjectType")} = 'user') = (${e("user")} is not null)),
  check (${e("user")} is null or ${e("subjectId")} = ${e("user")}::text),
  unique nulls not distinct (${e("tenant")}, ${e("program")}, ${e("subjectType")}, ${e("subjectId")})
);${key("enrollments", "subject_key", `(${e("tenant")}, ${e("program")}, ${e("subjectType")}, ${e("subjectId")}) nulls not distinct`)}
create index if not exists ${name("enrollments", "program_idx")} on ${enrollments} (${e("tenant")}, ${e("program")}, ${e("status")});
create index if not exists ${name("enrollments", "subject_idx")} on ${enrollments} (${e("tenant")}, ${e("subjectType")}, ${e("subjectId")});
create index if not exists ${name("enrollments", "user_idx")} on ${enrollments} (${e("user")});

-- A completed step, or an open one whose program step has an assignee or a
-- due date (completed_at is null until it is done).
create table if not exists ${steps} (
  ${s("enrollment")} uuid not null references ${enrollments} (${e("id")}) on delete cascade,
  ${s("tenant")} ${ctx.idType},
  ${s("step")} text not null,${optional("steps", "assigneeRole", (c) => `${c} text check (${c} is null or ${c} ~ '^[a-z][a-z0-9_-]{0,62}$')`)}${optional("steps", "assigneeUser", (c) => `${c} uuid references auth.users (id) on delete set null`)}${optional("steps", "dueAt", (c) => `${c} timestamptz`)}
  ${s("completedBy")} uuid,
  ${s("completedAt")} timestamptz default now(),
  primary key (${s("enrollment")}, ${s("step")})
);${key("steps", "step_key", `(${s("enrollment")}, ${s("step")})`)}${scheduleIndexes(ctx, name)}

${lockTable(programs, { read: true })}
drop policy if exists ${name("programs", "read")} on ${programs};
${renderPolicy(makePolicy({ table: programs, name: name("programs", "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(p("tenant"), read) }), { target: programs })}
${lockTable(enrollments, { read: true })}
drop policy if exists ${name("enrollments", "read")} on ${enrollments};
${renderPolicy(makePolicy({ table: enrollments, name: name("enrollments", "read"), command: "select", roles: ["authenticated"], using: `${e("user")} = (select auth.uid()) or ${ctx.scope.check(e("tenant"), read)}` }), { target: enrollments })}
${lockTable(steps, { read: true })}
drop policy if exists ${name("steps", "read")} on ${steps};
${renderPolicy(makePolicy({ table: steps, name: name("steps", "read"), command: "select", roles: ["authenticated"], using: `exists (select 1 from ${enrollments} x where x.${e("id")} = ${steps}.${s("enrollment")})` }), { target: steps })}
`;
}

function build(ctx: BlockSqlContext): string {
  return `${schemaPreamble(ctx)}
${enrollmentTables(ctx)}
${enrollmentsFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_enrollment_program",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "enroll",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "enrollment",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "complete_enrollment_step",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    { name: "reset_enrollment_step", args: ["uuid", "text"], returns: "jsonb" },
    { name: "cancel_enrollment", args: ["uuid"], returns: "jsonb" },
  ];
}

export const ENROLLMENTS: BlockSqlDefinition = {
  internal: [
    "enrollment_ensure",
    "enrollment_mark",
    "enrollment_json",
    "enrollment_step",
    "enrollment_schedule",
  ],
  name: "enrollments",
  scopes: ["tenant"],
  title: "Enrollments",
  description:
    "Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  before: "onboarding",
  names: NAMES,
  contract,
  build,
};
