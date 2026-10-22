import type { CoursesEvents } from "../../blocks/courses/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { courseAuthoringFunctions } from "./courses-authoring.ts";
import { courseLearningFunctions } from "./courses-learning.ts";
import { COURSE_KEYS, courseEnrollments } from "./courses-sql.ts";

const COURSE_PAYLOAD = ["organizationId", "id", "key", "status"] as const;

const LEARNER_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "enrollmentId",
] as const;

const COURSE_ITEM_PAYLOAD = [
  "organizationId",
  "id",
  "courseId",
  "userId",
  "enrollmentId",
] as const;

const EVENTS: BlockSqlEvents<CoursesEvents> = {
  "course.saved": { subject: "courses", payload: COURSE_PAYLOAD },
  "course.deleted": { subject: "courses", payload: COURSE_PAYLOAD },
  "course.enrolled": { subject: "courses", payload: LEARNER_PAYLOAD },
  "course.unenrolled": { subject: "courses", payload: LEARNER_PAYLOAD },
  "course.completed": { subject: "courses", payload: LEARNER_PAYLOAD },
  "course_lesson.completed": {
    subject: "course-lessons",
    payload: COURSE_ITEM_PAYLOAD,
  },
  "course_certificate.issued": {
    subject: "course-certificates",
    payload: COURSE_ITEM_PAYLOAD,
  },
  "course_certificate.revoked": {
    subject: "course-certificates",
    payload: COURSE_ITEM_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    course: {
      table: "courses",
      singular: "course",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
        search: { title: "title", body: ["summary"] },
      },
    },
    course_module: { table: "modules", singular: "course_module" },
    course_lesson: { table: "lessons", singular: "course_lesson" },
    course_certificate: {
      table: "certificates",
      singular: "course_certificate",
    },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    courses: {
      name: "courses",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        title: "title",
        summary: "summary",
        status: "status",
        certificate: "issues_certificate",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    modules: {
      name: "course_modules",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        course: "course_id",
        title: "title",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    lessons: {
      name: "course_lessons",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        course: "course_id",
        module: "module_id",
        title: "title",
        kind: "kind",
        body: "body",
        mediaUrl: "media_url",
        form: "form_id",
        required: "required",
        minutes: "duration_minutes",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    progress: {
      name: "course_lesson_progress",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        enrollment: "enrollment_id",
        lesson: "lesson_id",
        tenant: "tenant_id",
        course: "course_id",
        user: "user_id",
        startedAt: "started_at",
        completedAt: "completed_at",
        attempts: "attempts",
        submission: "submission_id",
        score: "score",
        maxScore: "max_score",
        passed: "passed",
        updatedAt: "updated_at",
      },
    },
    certificates: {
      name: "course_certificates",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        course: "course_id",
        enrollment: "enrollment_id",
        user: "user_id",
        code: "code",
        issuedAt: "issued_at",
        revokedAt: "revoked_at",
      },
    },
  },
};

function courseTables(ctx: BlockSqlContext): string {
  const enrolled = courseEnrollments(ctx);
  const courses = ctx.table("courses");
  const modules = ctx.table("modules");
  const lessons = ctx.table("lessons");
  const progress = ctx.table("progress");
  const certificates = ctx.table("certificates");
  const enrollments = enrolled.table("enrollments");
  const enrollmentId = enrolled.col("enrollments", "id");
  const c = (column: string): string => ctx.col("courses", column);
  const m = (column: string): string => ctx.col("modules", column);
  const l = (column: string): string => ctx.col("lessons", column);
  const p = (column: string): string => ctx.col("progress", column);
  const k = (column: string): string => ctx.col("certificates", column);
  const keys = moduleOperations("courses");
  const read = ctx.permission("read", keys.read);
  const enroll = ctx.permission("enroll", keys.enroll);
  const manage = ctx.permission("manage", keys.manage);
  const extras = ctx.extraColumns("courses", COURSE_KEYS);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  return `create table if not exists ${courses} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("key")} text not null check (${c("key")} ~ '^[a-z][a-z0-9-]{0,62}$'),
  ${c("title")} text not null check (length(${c("title")}) between 1 and 200),
  ${c("summary")} text check (${c("summary")} is null or length(${c("summary")}) <= 2000),
  ${c("status")} text not null default 'draft' check (${c("status")} in ('draft', 'published', 'archived')),
  ${c("certificate")} boolean not null default true,
  ${c("createdBy")} uuid,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  unique (${c("tenant")}, ${c("key")})
);${addExtraColumns(courses, extras)}

create table if not exists ${modules} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("course")} uuid not null references ${courses} (${c("id")}) on delete cascade,
  ${m("title")} text not null check (length(${m("title")}) between 1 and 200),
  -- A fractional rank key (ADR 0021): modules sort by it within the course.
  ${m("rank")} text collate "C" not null,
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now()
);
create index if not exists ${name("modules", "parent_idx")} on ${modules} (${m("course")}, ${m("rank")});

create table if not exists ${lessons} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("course")} uuid not null references ${courses} (${c("id")}) on delete cascade,
  ${l("module")} uuid not null references ${modules} (${m("id")}) on delete cascade,
  ${l("title")} text not null check (length(${l("title")}) between 1 and 200),
  ${l("kind")} text not null default 'content' check (${l("kind")} in ('content', 'video', 'quiz')),
  -- The lesson's content, such as a rich-text document; only enrolled
  -- learners and the course's managers read it.
  ${l("body")} jsonb,
  ${l("mediaUrl")} text check (${l("mediaUrl")} is null or (${l("mediaUrl")} ~ '^https?://' and length(${l("mediaUrl")}) <= 2000)),
  -- The forms form a quiz lesson grades; a passed submission completes it.
  ${l("form")} uuid,
  -- Required lessons are the steps of the course's enrollment program.
  ${l("required")} boolean not null default true,
  ${l("minutes")} integer check (${l("minutes")} is null or ${l("minutes")} between 1 and 10000),
  ${l("rank")} text collate "C" not null,
  ${l("createdAt")} timestamptz not null default now(),
  ${l("updatedAt")} timestamptz not null default now(),
  check ((${l("kind")} = 'quiz') = (${l("form")} is not null))
);
create index if not exists ${name("lessons", "module_idx")} on ${lessons} (${l("module")}, ${l("rank")});
create index if not exists ${name("lessons", "parent_idx")} on ${lessons} (${l("course")});
create index if not exists ${name("lessons", "form_idx")} on ${lessons} (${l("form")}) where ${l("form")} is not null;

-- A learner's state in one lesson of the course they are enrolled in. The
-- enrollment's steps hold the completed required lessons; this holds when
-- each lesson started and finished, and a quiz's attempts and grade.
create table if not exists ${progress} (
  ${p("enrollment")} uuid not null references ${enrollments} (${enrollmentId}) on delete cascade,
  ${p("lesson")} uuid not null references ${lessons} (${l("id")}) on delete cascade,
  ${p("tenant")} ${ctx.idType} not null,
  ${p("course")} uuid not null references ${courses} (${c("id")}) on delete cascade,
  ${p("user")} uuid not null references auth.users (id) on delete cascade,
  ${p("startedAt")} timestamptz not null default now(),
  ${p("completedAt")} timestamptz,
  ${p("attempts")} integer not null default 0 check (${p("attempts")} >= 0),
  ${p("submission")} uuid,
  ${p("score")} numeric,
  ${p("maxScore")} numeric,
  ${p("passed")} boolean,
  ${p("updatedAt")} timestamptz not null default now(),
  constraint ${name("progress", "pkey")} primary key (${p("enrollment")}, ${p("lesson")})
);
create index if not exists ${name("progress", "lesson_idx")} on ${progress} (${p("lesson")});
create index if not exists ${name("progress", "parent_idx")} on ${progress} (${p("course")});
create index if not exists ${name("progress", "user_idx")} on ${progress} (${p("user")});

-- One per completed enrollment of a course that issues certificates. code is
-- the random value a verification link carries.
create table if not exists ${certificates} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("course")} uuid not null references ${courses} (${c("id")}) on delete cascade,
  ${k("enrollment")} uuid not null references ${enrollments} (${enrollmentId}) on delete cascade,
  ${k("user")} uuid not null references auth.users (id) on delete cascade,
  ${k("code")} text not null unique check (${k("code")} ~ '^[0-9a-f]{32}$'),
  ${k("issuedAt")} timestamptz not null default now(),
  ${k("revokedAt")} timestamptz,
  constraint ${name("certificates", "enrollment_key")} unique (${k("enrollment")})
);
create index if not exists ${name("certificates", "parent_idx")} on ${certificates} (${k("course")});
create index if not exists ${name("certificates", "user_idx")} on ${certificates} (${k("user")});

${lockTable(courses, { read: true })}
drop policy if exists ${name("courses", "read")} on ${courses};
create policy ${name("courses", "read")} on ${courses} for select to authenticated
  using ((${c("status")} = 'published' and ${ctx.scope.check(c("tenant"), read)}) or ${ctx.scope.check(c("tenant"), manage)});
${lockTable(modules, { read: true })}
drop policy if exists ${name("modules", "read")} on ${modules};
create policy ${name("modules", "read")} on ${modules} for select to authenticated
  using (exists (select 1 from ${courses} x where x.${c("id")} = ${modules}.${m("course")}));
${lockTable(lessons, { read: true })}
drop policy if exists ${name("lessons", "read")} on ${lessons};
create policy ${name("lessons", "read")} on ${lessons} for select to authenticated
  using (${ctx.scope.check(l("tenant"), manage)});
${lockTable(progress, { read: true })}
drop policy if exists ${name("progress", "read")} on ${progress};
create policy ${name("progress", "read")} on ${progress} for select to authenticated
  using (${p("user")} = (select auth.uid()) or ${ctx.scope.check(p("tenant"), enroll)} or ${ctx.scope.check(p("tenant"), manage)});
${lockTable(certificates, { read: true })}
drop policy if exists ${name("certificates", "read")} on ${certificates};
create policy ${name("certificates", "read")} on ${certificates} for select to authenticated
  using (${k("user")} = (select auth.uid()) or ${ctx.scope.check(k("tenant"), enroll)} or ${ctx.scope.check(k("tenant"), manage)});
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Courses of modules and lessons ordered by rank keys. Each course runs as
-- the enrollment program course:<id>, whose steps are its required lessons.
${courseTables(ctx)}
${courseAuthoringFunctions(ctx)}
${courseLearningFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_course", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_courses", args: ["{id}", "text"], returns: "jsonb" },
    { name: "course_outline", args: ["uuid"], returns: "jsonb" },
    { name: "course_lesson", args: ["uuid"], returns: "jsonb" },
    { name: "enroll_in_course", args: ["uuid", "uuid"], returns: "jsonb" },
    {
      name: "complete_course_lesson",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "course_progress", args: ["uuid", "uuid"], returns: "jsonb" },
  ];
}

export const COURSES: BlockSqlDefinition = {
  internal: [
    "course_json",
    "course_steps",
    "course_sync",
    "course_finish",
    "course_learner_json",
    "course_lesson_done",
  ],
  name: "courses",
  scopes: ["tenant"],
  title: "Courses",
  description:
    "Courses of modules and lessons ordered by rank keys, with quiz lessons graded by forms, per-lesson progress, completion and certificates. Each course runs as an enrollment program, so learners enroll through enrollments.",
  requires: ["tenant", "access", "enrollments"],
  integrates: ["forms", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
