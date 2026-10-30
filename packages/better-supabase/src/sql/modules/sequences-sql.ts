import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * The columns sequences adds to the enrollments table for a recipient's run,
 * after the sequence entity's singular (`sequence_address`). The step that runs
 * next is the enrollment's open step row, due when it runs.
 */
const RUN_COLUMNS = {
  sequence: "id",
  address: "address",
  name: "name",
  account: "mail_account_id",
  thread: "mail_thread_id",
  attempts: "attempts",
  lastError: "last_error",
  variables: "variables",
} as const;

/** A run column of the enrollments table. */
export type RunColumn = keyof typeof RUN_COLUMNS;

const noun = (ctx: BlockSqlContext): string =>
  ctx.resolved.entities["sequence"]?.to.singular ?? "sequence";

const runColumn =
  (ctx: BlockSqlContext) =>
  (column: RunColumn): string =>
    sqlIdent(`${noun(ctx)}_${RUN_COLUMNS[column]}`);

/** The SQL pieces the sequences function files share. */
export interface SequenceSql {
  readonly fn: (name: string) => string;
  /** A column of the sequences table. */
  readonly s: (column: string) => string;
  /** A column sequences adds to the enrollments table. */
  readonly r: (column: RunColumn) => string;
  /** A column of the enrollments table. */
  readonly e: (column: string) => string;
  /** A column of the enrollment steps table. */
  readonly d: (column: string) => string;
  readonly has: (table: string, column: string) => boolean;
  /** `alias`'s optional column of `table`, or null when the table has none. */
  readonly opt: (alias: string, table: string, column: string) => string;
  /** A text expression written to a fixed-value column of `table`. */
  readonly cast: (table: string, column: string, value: string) => string;
  readonly sequences: string;
  readonly enrollments: string;
  /** The enrollment steps table: completed steps and the open one. */
  readonly done: string;
  /** Mail-sync, when it is installed and managed. */
  readonly mail: BlockSqlContext | undefined;
  /** Work-items, when it is installed and managed. */
  readonly tasks: BlockSqlContext | undefined;
  /** Parties, when it is installed and managed. */
  readonly parties: BlockSqlContext | undefined;
  readonly read: string;
  readonly enroll: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly sequenceMissing: string;
  readonly memberMissing: string;
  readonly program: (sequence: string) => string;
  readonly sequenceJson: (row: string) => string;
  /**
   * The run status of enrollment row `row`: `active`, `paused`, `completed` or
   * `exited`.
   */
  readonly runStatus: (row: string) => string;
  /** The open step row of enrollment `id`: its step and when it runs. */
  readonly openStep: (id: string, into: string) => string;
}

const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined => {
  if (!ctx.installed(module)) {
    return undefined;
  }

  const other = ctx.of(module);

  return other.manages ? other : undefined;
};

/** The enrollments block a sequence runs on, checked for the run columns. */
export function sequenceEnrollments(ctx: BlockSqlContext): BlockSqlContext {
  const enrolled = ctx.of("enrollments");

  if (!enrolled.manages) {
    throw new TypeError(
      "blocks.sequences: each sequence runs as an enrollment program, so install enrollments in managed mode",
    );
  }

  for (const [table, column] of [
    ["enrollments", "pausedAt"],
    ["enrollments", "cancelReason"],
    ["steps", "dueAt"],
  ] as const) {
    if (!enrolled.has(table, column)) {
      throw new TypeError(
        `blocks.sequences: a run keeps its state in the ${column} column of the enrollments ${table} table, so keep it`,
      );
    }
  }

  return enrolled;
}

/**
 * The run columns sequences adds to the enrollments table, with their indexes.
 * The version 2 upgrade writes them too, so its rows can move before this
 * module renders.
 */
export function sequenceRunColumns(ctx: BlockSqlContext): string {
  const enrolled = sequenceEnrollments(ctx);
  const enrollments = enrolled.table("enrollments");
  const steps = enrolled.table("steps");
  const e = (column: string): string => enrolled.col("enrollments", column);
  const d = (column: string): string => enrolled.col("steps", column);
  const mail = managed(ctx, "mail-sync");
  const r = runColumn(ctx);
  const table = enrolled.tableName("enrollments").name;
  const stepsTable = enrolled.tableName("steps").name;

  const mailbox =
    mail === undefined
      ? ""
      : ` references ${mail.table("accounts")} (${mail.col("accounts", "id")}) on delete set null`;

  const thread =
    mail === undefined
      ? ""
      : ` references ${mail.table("threads")} (${mail.col("threads", "id")}) on delete set null`;

  const columns = [
    `${r("sequence")} uuid references ${ctx.table("sequences")} (${ctx.col("sequences", "id")}) on delete cascade`,
    `${r("address")} text check (${r("address")} is null or (length(${r("address")}) <= 320 and ${r("address")} ~ '^[^@[:space:]]+@[^@[:space:]]+$'))`,
    `${r("name")} text check (${r("name")} is null or length(${r("name")}) <= 200)`,
    `${r("account")} uuid${mailbox}`,
    `${r("thread")} uuid${thread}`,
    `${r("attempts")} integer not null default 0 check (${r("attempts")} >= 0)`,
    `${r("lastError")} text check (${r("lastError")} is null or length(${r("lastError")}) <= 2000)`,
    `${r("variables")} jsonb not null default '{}' check (jsonb_typeof(${r("variables")}) = 'object')`,
  ];

  return `-- A recipient's run is their enrollment in the program sequence:<id>: these
-- columns say who it goes to and how sending went, and the open step row is
-- the step that runs next, due when it runs.
${columns.map((column) => `alter table ${enrollments} add column if not exists ${column};`).join("\n")}
create index if not exists ${sqlIdent(`${table}_${noun(ctx)}_idx`)} on ${enrollments} (${r("sequence")}, ${e("status")}) where ${r("sequence")} is not null;
create index if not exists ${sqlIdent(`${table}_${noun(ctx)}_address_idx`)} on ${enrollments} (${e("tenant")}, lower(${r("address")})) where ${r("sequence")} is not null and ${e("status")} = 'active';
create index if not exists ${sqlIdent(`${table}_${noun(ctx)}_account_idx`)} on ${enrollments} (${r("account")}) where ${r("account")} is not null;
create index if not exists ${sqlIdent(`${table}_${noun(ctx)}_thread_idx`)} on ${enrollments} (${r("thread")}) where ${r("thread")} is not null;
create index if not exists ${sqlIdent(`${stepsTable}_open_due_idx`)} on ${steps} (${d("dueAt")}) where ${d("completedAt")} is null;`;
}

/** The names and helpers the sequences function files build on. */
export function sequenceSql(ctx: BlockSqlContext): SequenceSql {
  const enrolled = sequenceEnrollments(ctx);
  const s = (column: string): string => ctx.col("sequences", column);
  const e = (column: string): string => enrolled.col("enrollments", column);
  const d = (column: string): string => enrolled.col("steps", column);
  const keys = moduleOperations("sequences");
  const done = enrolled.table("steps");

  return {
    fn: (name) => ctx.fn(name),
    s,
    r: runColumn(ctx),
    e,
    d,
    has: (table, column) => ctx.has(table, column),
    opt: (alias, table, column) =>
      ctx.has(table, column) ? `${alias}.${ctx.col(table, column)}` : "null",
    cast: (table, column, value) => ctx.cast(table, column, value),
    sequences: ctx.table("sequences"),
    enrollments: enrolled.table("enrollments"),
    done,
    mail: managed(ctx, "mail-sync"),
    tasks: managed(ctx, "tasks"),
    parties: managed(ctx, "contacts"),
    read: ctx.permission("read", keys.read),
    enroll: ctx.permission("enroll", keys.enroll),
    manage: ctx.permission("manage", keys.manage),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("SEQUENCE_INVALID", message, "22023"),
    forbidden: (message) => fail("SEQUENCE_FORBIDDEN", message),
    sequenceMissing: fail("SEQUENCE_NOT_FOUND", "sequence not found", "P0002"),
    memberMissing: fail(
      "SEQUENCE_ENROLLMENT_NOT_FOUND",
      "sequence enrollment not found",
      "P0002",
    ),
    program: (sequence) => `('sequence:' || ${sequence}::text)`,
    sequenceJson: (row) =>
      `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'key', ${row}.${s("key")}, 'name', ${row}.${s("name")}, 'description', ${ctx.has("sequences", "description") ? `${row}.${s("description")}` : "null"}, 'status', ${row}.${s("status")}, 'exitOnReply', ${row}.${s("exitOnReply")}, 'accountId', ${row}.${s("account")}, 'steps', ${row}.${s("steps")}, 'version', ${row}.${s("version")}, 'createdBy', ${row}.${s("createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`,
    runStatus: (row) =>
      `(case when ${row}.${e("status")} = 'cancelled' then 'exited' when ${row}.${e("status")} = 'completed' then 'completed' when ${row}.${e("pausedAt")} is not null then 'paused' else 'active' end)`,
    openStep: (id, into) =>
      `select o.${d("step")}, o.${d("dueAt")} into ${into} from ${done} o where o.${d("enrollment")} = ${id} and o.${d("completedAt")} is null limit 1;`,
  };
}
