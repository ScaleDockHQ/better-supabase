import type { EnrollmentsEvents } from "../../blocks/enrollments/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { enrollmentsFunctions } from "./enrollments-functions.ts";

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
  "enrollment_program.saved": {
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
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
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
      lifecycle: { tenant: "tenant", user: "user", export: true },
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
        completedAt: "completed_at",
        cancelledAt: "cancelled_at",
        updatedAt: "updated_at",
      },
    },
    steps: {
      name: "enrollment_steps",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        enrollment: "enrollment_id",
        tenant: "tenant_id",
        step: "step",
        completedBy: "completed_by",
        completedAt: "completed_at",
      },
    },
  },
};

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

  return `create table if not exists ${programs} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("key")} text not null check (${p("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("description")} text check (${p("description")} is null or length(${p("description")}) <= 2000),
  -- The subject types it enrolls; empty enrolls any.
  ${p("subjectTypes")} text[] not null default '{}',
  -- [{ id, title, description }], in order.
  ${p("steps")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${p("steps")}) = 'array'),
  ${p("enabled")} boolean not null default true,
  ${p("version")} integer not null default 1,
  ${p("createdBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("key")})
);

-- One per program and subject. A user's own onboarding checklist has no
-- tenant; user_id is set for user subjects so the row goes with the user.
create table if not exists ${enrollments} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType},
  ${e("program")} text not null check (length(${e("program")}) between 1 and 200),
  ${e("programVersion")} integer,
  ${e("subjectType")} text not null check (${e("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${e("subjectId")} text not null check (length(${e("subjectId")}) between 1 and 200),
  ${e("user")} uuid references auth.users (id) on delete cascade,
  -- The program's step ids when it enrolled or last changed.
  ${e("steps")} text[] not null default '{}',
  ${e("completedSteps")} integer not null default 0 check (${e("completedSteps")} >= 0),
  ${e("status")} text not null default 'active' check (${e("status")} in ('active', 'completed', 'cancelled')),
  ${e("enrolledBy")} uuid,
  ${e("enrolledAt")} timestamptz not null default now(),
  ${e("completedAt")} timestamptz,
  ${e("cancelledAt")} timestamptz,
  ${e("updatedAt")} timestamptz not null default now(),
  check ((${e("subjectType")} = 'user') = (${e("user")} is not null)),
  check (${e("user")} is null or ${e("subjectId")} = ${e("user")}::text),
  unique nulls not distinct (${e("tenant")}, ${e("program")}, ${e("subjectType")}, ${e("subjectId")})
);
create index if not exists ${name("enrollments", "program_idx")} on ${enrollments} (${e("tenant")}, ${e("program")}, ${e("status")});
create index if not exists ${name("enrollments", "subject_idx")} on ${enrollments} (${e("tenant")}, ${e("subjectType")}, ${e("subjectId")});
create index if not exists ${name("enrollments", "user_idx")} on ${enrollments} (${e("user")});

create table if not exists ${steps} (
  ${s("enrollment")} uuid not null references ${enrollments} (${e("id")}) on delete cascade,
  ${s("tenant")} ${ctx.idType},
  ${s("step")} text not null,
  ${s("completedBy")} uuid,
  ${s("completedAt")} timestamptz not null default now(),
  primary key (${s("enrollment")}, ${s("step")})
);

${lockTable(programs, { read: true })}
drop policy if exists ${name("programs", "read")} on ${programs};
create policy ${name("programs", "read")} on ${programs} for select to authenticated
  using (${ctx.scope.check(p("tenant"), read)});
${lockTable(enrollments, { read: true })}
drop policy if exists ${name("enrollments", "read")} on ${enrollments};
create policy ${name("enrollments", "read")} on ${enrollments} for select to authenticated
  using (${e("user")} = (select auth.uid()) or ${ctx.scope.check(e("tenant"), read)});
${lockTable(steps, { read: true })}
drop policy if exists ${name("steps", "read")} on ${steps};
create policy ${name("steps", "read")} on ${steps} for select to authenticated
  using (exists (select 1 from ${enrollments} x where x.${e("id")} = ${steps}.${s("enrollment")}));
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
  ],
  name: "enrollments",
  scopes: ["tenant"],
  title: "Enrollments",
  description:
    "Programs of steps per organization, and enrollments of a party, a member or any subject in them with step progress and completion. Onboarding checklists run on it.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  before: "onboarding",
  names: NAMES,
  contract,
  build,
};
