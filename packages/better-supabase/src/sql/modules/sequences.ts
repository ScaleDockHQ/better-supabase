import type { SequencesEvents } from "../../blocks/sequences/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { sequenceFunctions } from "./sequences-functions.ts";
import { sequenceRunner } from "./sequences-runner.ts";
import { sequenceSql } from "./sequences-sql.ts";

const SEQUENCE_PAYLOAD = ["organizationId", "id", "key", "status"] as const;

const MEMBER_PAYLOAD = [
  "organizationId",
  "id",
  "sequenceId",
  "subjectType",
  "subjectId",
  "status",
  "step",
  "reason",
] as const;

const EVENTS: BlockSqlEvents<SequencesEvents> = {
  "sequence.saved": { subject: "sequences", payload: SEQUENCE_PAYLOAD },
  "sequence.deleted": { subject: "sequences", payload: SEQUENCE_PAYLOAD },
  "sequence_enrollment.created": {
    subject: "sequence-enrollments",
    payload: MEMBER_PAYLOAD,
  },
  "sequence_enrollment.step_completed": {
    subject: "sequence-enrollments",
    payload: MEMBER_PAYLOAD,
  },
  "sequence_enrollment.paused": {
    subject: "sequence-enrollments",
    payload: MEMBER_PAYLOAD,
  },
  "sequence_enrollment.resumed": {
    subject: "sequence-enrollments",
    payload: MEMBER_PAYLOAD,
  },
  "sequence_enrollment.exited": {
    subject: "sequence-enrollments",
    payload: MEMBER_PAYLOAD,
  },
  "sequence_enrollment.completed": {
    subject: "sequence-enrollments",
    payload: MEMBER_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    sequence: { table: "sequences", singular: "sequence", primary: true },
    sequence_enrollment: { table: "members", singular: "sequence_enrollment" },
  },
  events: EVENTS,
  options: ["maxAttempts", "retryMinutes"],
  tables: {
    sequences: {
      name: "sequences",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        description: "description",
        status: "status",
        exitOnReply: "exit_on_reply",
        account: "mail_account_id",
        steps: "steps",
        version: "version",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    members: {
      name: "sequence_enrollments",
      lifecycle: { tenant: "tenant", user: "enrolledBy", export: true },
      columns: {
        enrollment: "enrollment_id",
        tenant: "tenant_id",
        sequence: "sequence_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        address: "address",
        name: "name",
        account: "mail_account_id",
        thread: "mail_thread_id",
        step: "step",
        nextRunAt: "next_run_at",
        status: "status",
        exitReason: "exit_reason",
        attempts: "attempts",
        lastError: "last_error",
        variables: "variables",
        enrolledBy: "enrolled_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

function sequenceTables(ctx: BlockSqlContext): string {
  const q = sequenceSql(ctx);
  const { s, r, mail } = q;
  const sequences = q.sequences;
  const members = q.members;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const mailbox =
    mail === undefined
      ? ""
      : ` references ${mail.table("accounts")} (${mail.col("accounts", "id")}) on delete set null`;

  const thread =
    mail === undefined
      ? ""
      : ` references ${mail.table("threads")} (${mail.col("threads", "id")}) on delete set null`;

  return `create table if not exists ${sequences} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("key")} text not null check (${s("key")} ~ '^[a-z][a-z0-9-]{0,62}$'),
  ${s("name")} text not null check (length(${s("name")}) between 1 and 200),
  ${s("description")} text check (${s("description")} is null or length(${s("description")}) <= 2000),
  ${s("status")} text not null default 'draft' check (${s("status")} in ('draft', 'active', 'paused', 'archived')),
  -- An inbound message on the thread, or from the recipient's address, ends
  -- the recipient's run.
  ${s("exitOnReply")} boolean not null default true,
  -- The mailbox email steps send from when the enrollment names none.
  ${s("account")} uuid${mailbox},
  -- The steps in order: [{ id, kind: email | task | wait, ... }]. Each is a
  -- step of the enrollment program sequence:<id>.
  ${s("steps")} jsonb not null default '[]' check (jsonb_typeof(${s("steps")}) = 'array'),
  ${s("version")} integer not null default 1 check (${s("version")} >= 1),
  ${s("createdBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now(),
  constraint ${name("sequences", "key_key")} unique (${s("tenant")}, ${s("key")})
);
create index if not exists ${name("sequences", "account_idx")} on ${sequences} (${s("account")}) where ${s("account")} is not null;

-- Where a recipient is in a sequence. The enrollment holds the completed
-- steps; this holds the next step, when it runs and who it goes to.
create table if not exists ${members} (
  ${r("enrollment")} uuid primary key references ${q.enrollments} (${q.e("id")}) on delete cascade,
  ${r("tenant")} ${ctx.idType} not null,
  ${r("sequence")} uuid not null references ${sequences} (${s("id")}) on delete cascade,
  ${r("subjectType")} text not null check (${r("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${r("subjectId")} text not null check (length(${r("subjectId")}) between 1 and 200),
  ${r("address")} text check (${r("address")} is null or (length(${r("address")}) <= 320 and ${r("address")} ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  ${r("name")} text check (${r("name")} is null or length(${r("name")}) <= 200),
  ${r("account")} uuid${mailbox},
  -- The thread the first email started; later emails reply on it.
  ${r("thread")} uuid${thread},
  -- The step that runs next, null once every step is done.
  ${r("step")} text,
  ${r("nextRunAt")} timestamptz,
  ${r("status")} text not null default 'active' check (${r("status")} in ('active', 'paused', 'completed', 'exited')),
  ${r("exitReason")} text check (${r("exitReason")} is null or ${r("exitReason")} in ('replied', 'manual', 'failed', 'archived')),
  ${r("attempts")} integer not null default 0 check (${r("attempts")} >= 0),
  ${r("lastError")} text check (${r("lastError")} is null or length(${r("lastError")}) <= 2000),
  -- Values for the {{key}} placeholders of the email steps.
  ${r("variables")} jsonb not null default '{}' check (jsonb_typeof(${r("variables")}) = 'object'),
  ${r("enrolledBy")} uuid,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  check ((${r("status")} = 'exited') = (${r("exitReason")} is not null))
);
create index if not exists ${name("members", "parent_idx")} on ${members} (${r("sequence")}, ${r("status")});
create index if not exists ${name("members", "due_idx")} on ${members} (${r("nextRunAt")}) where ${r("status")} = 'active';
create index if not exists ${name("members", "subject_idx")} on ${members} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")});
create index if not exists ${name("members", "address_idx")} on ${members} (${r("tenant")}, lower(${r("address")})) where ${r("status")} in ('active', 'paused');
create index if not exists ${name("members", "account_idx")} on ${members} (${r("account")}) where ${r("account")} is not null;
create index if not exists ${name("members", "thread_idx")} on ${members} (${r("thread")}) where ${r("thread")} is not null;

${lockTable(sequences, { read: true })}
drop policy if exists ${name("sequences", "read")} on ${sequences};
create policy ${name("sequences", "read")} on ${sequences} for select to authenticated
  using (${ctx.scope.check(s("tenant"), q.read)});
${lockTable(members, { read: true })}
drop policy if exists ${name("members", "read")} on ${members};
create policy ${name("members", "read")} on ${members} for select to authenticated
  using (${ctx.scope.check(r("tenant"), q.read)});
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Outreach sequences: steps that send email, create a task or wait. Each
-- sequence runs as the enrollment program sequence:<id>, whose steps are the
-- sequence's steps; a reply ends a recipient's run.
${sequenceTables(ctx)}
${sequenceFunctions(ctx)}
${sequenceRunner(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_sequence", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_sequences", args: ["{id}", "text"], returns: "jsonb" },
    { name: "get_sequence", args: ["uuid"], returns: "jsonb" },
    { name: "delete_sequence", args: ["uuid"], returns: "boolean" },
    {
      name: "enroll_in_sequence",
      args: ["uuid", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "change_sequence_enrollment",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "list_sequence_enrollments",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    { name: "run_due_sequences", args: ["integer"], returns: "jsonb" },
    {
      name: "sequence_step_sent",
      args: ["uuid", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "sequence_step_failed",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
  ];
}

export const SEQUENCES: BlockSqlDefinition = {
  internal: [
    "sequence_member_json",
    "sequence_place",
    "sequence_exit",
    "sequence_steps_check",
    "sequence_step_done",
    "sequence_resync",
    "sequence_mail_replied",
  ],
  name: "sequences",
  scopes: ["tenant"],
  title: "Sequences",
  description:
    "Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.",
  requires: ["memberships", "permissions", "enrollments"],
  integrates: ["mail-sync", "contacts", "tasks", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
