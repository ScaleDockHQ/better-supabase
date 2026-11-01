import type { SequencesEvents } from "../../blocks/sequences/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { enrollmentStateColumns, enrollmentTables } from "./enrollments.ts";
import { sequenceFunctions } from "./sequences-functions.ts";
import { sequenceRunner } from "./sequences-runner.ts";
import {
  sequenceEnrollments,
  sequenceRunColumns,
  sequenceSql,
} from "./sequences-sql.ts";

const SEQUENCE_PAYLOAD = ["organizationId", "id", "key", "status"] as const;

const EVENTS: BlockSqlEvents<SequencesEvents> = {
  "sequence.created": { subject: "sequences", payload: SEQUENCE_PAYLOAD },
  "sequence.updated": { subject: "sequences", payload: SEQUENCE_PAYLOAD },
  "sequence.deleted": { subject: "sequences", payload: SEQUENCE_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  entities: {
    sequence: { table: "sequences", singular: "sequence", primary: true },
  },
  events: EVENTS,
  hooks: [
    "before_sequence_save",
    "after_sequence_save",
    "before_sequence_enroll",
    "after_sequence_enroll",
  ],
  options: ["maxAttempts", "retryMinutes"],
  tables: {
    sequences: {
      name: "sequences",
      app: {},
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
      optional: ["description"],
      typed: ["status"],
    },
  },
};

function sequenceTables(ctx: BlockSqlContext): string {
  const q = sequenceSql(ctx);
  const { s, mail } = q;
  const sequences = q.sequences;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const mailbox =
    mail === undefined
      ? ""
      : ` references ${mail.table("accounts")} (${mail.col("accounts", "id")}) on delete set null`;

  return `create table if not exists ${sequences} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("key")} text not null check (${s("key")} ~ '^[a-z][a-z0-9-]{0,62}$'),
  ${s("name")} text not null check (length(${s("name")}) between 1 and 200),
${q.has("sequences", "description") ? `  ${s("description")} text check (${s("description")} is null or length(${s("description")}) <= 2000),\n` : ""}  ${s("status")} text not null default 'draft' check (${s("status")} in ('draft', 'active', 'paused', 'archived')),
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

${sequenceRunColumns(ctx)}

${lockTable(sequences, { read: true })}
drop policy if exists ${name("sequences", "read")} on ${sequences};
${renderPolicy(makePolicy({ table: sequences, name: name("sequences", "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(s("tenant"), q.read) }), { target: sequences })}
`;
}

/**
 * Version 1 kept each run in sequence_enrollments. Version 2 keeps it on the
 * enrollment: the run columns take the recipient and the sending state, a
 * paused run sets paused_at, an exited one keeps its exit reason in
 * cancel_reason, and the step that runs next becomes the open step row, due at
 * the run's next_run_at. Then sequence_enrollments is dropped.
 */
function enrollmentsUpgrade(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const q = sequenceSql(ctx);
  const enrolled = sequenceEnrollments(ctx);
  const { e, d, r } = q;
  const old = `${ctx.schema}.sequence_enrollments`;
  const field = (column: string): string => `(to_jsonb(m) ->> '${column}')`;

  return `${enrollmentTables(enrolled)}
${enrollmentStateColumns(enrolled)}
${sequenceRunColumns(ctx)}
do $upgrade$
begin
  if to_regclass(${sqlString(`${ctx.schemaName}.sequence_enrollments`)}) is null then
    return;
  end if;
  update ${q.enrollments} x
  set ${r("sequence")} = m.sequence_id, ${r("address")} = m.address, ${r("name")} = m.name,
    ${r("account")} = m.mail_account_id, ${r("thread")} = m.mail_thread_id, ${r("attempts")} = m.attempts,
    ${r("lastError")} = ${field("last_error")}, ${r("variables")} = m.variables,
    ${e("pausedAt")} = case when m.status::text = 'paused' and x.${e("status")} = 'active' then m.updated_at end,
    ${e("cancelReason")} = case when x.${e("status")} = 'cancelled' then m.exit_reason::text end
  from ${old} m
  where x.${e("id")} = m.enrollment_id;
  insert into ${q.done} (${d("enrollment")}, ${d("tenant")}, ${d("step")}, ${d("dueAt")}, ${d("completedBy")}, ${d("completedAt")})
  select m.enrollment_id, m.tenant_id, m.step, m.next_run_at, null, null
  from ${old} m
  join ${q.enrollments} x on x.${e("id")} = m.enrollment_id
  where m.step is not null and m.status::text in ('active', 'paused') and x.${e("status")} = 'active'
  on conflict do nothing;
  drop table ${old};
end;
$upgrade$;`;
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
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Sequence runs live on enrollments: each sequence_enrollments row moves onto its enrollment in the program sequence:<id>, its next step becomes the open step row, and sequence_enrollments is dropped.",
      sql: enrollmentsUpgrade,
    },
  ],
  names: NAMES,
  contract,
  build,
};
