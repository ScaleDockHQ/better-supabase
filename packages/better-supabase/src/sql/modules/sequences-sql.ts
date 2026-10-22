import type { BlockSqlContext } from "../context.ts";

import { fail, SERVICE_CALLER } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The SQL pieces the sequences function files share. */
export interface SequenceSql {
  readonly fn: (name: string) => string;
  /** A column of the sequences table. */
  readonly s: (column: string) => string;
  /** A column of the sequence enrollments table. */
  readonly r: (column: string) => string;
  /** A column of the enrollments table. */
  readonly e: (column: string) => string;
  /** A column of the enrollment steps table, the completed steps. */
  readonly d: (column: string) => string;
  readonly sequences: string;
  readonly members: string;
  readonly enrollments: string;
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
   * Records an event of `v_member`, a row of the sequence enrollments table,
   * with `step` and `reason` as SQL expressions. `false` leaves it out of the
   * audit log, for what the runner does.
   */
  readonly memberRecord: (
    type: string,
    summary: string | false,
    step?: string,
    reason?: string,
  ) => string;
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

/** The names and helpers the sequences function files build on. */
export function sequenceSql(ctx: BlockSqlContext): SequenceSql {
  const enrolled = ctx.of("enrollments");

  if (!enrolled.manages) {
    throw new TypeError(
      "blocks.sequences: each sequence runs as an enrollment program, so install enrollments in managed mode",
    );
  }

  const s = (column: string): string => ctx.col("sequences", column);
  const r = (column: string): string => ctx.col("members", column);
  const keys = moduleOperations("sequences");

  return {
    fn: (name) => ctx.fn(name),
    s,
    r,
    e: (column) => enrolled.col("enrollments", column),
    d: (column) => enrolled.col("steps", column),
    sequences: ctx.table("sequences"),
    members: ctx.table("members"),
    enrollments: enrolled.table("enrollments"),
    done: enrolled.table("steps"),
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
      `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'key', ${row}.${s("key")}, 'name', ${row}.${s("name")}, 'description', ${row}.${s("description")}, 'status', ${row}.${s("status")}, 'exitOnReply', ${row}.${s("exitOnReply")}, 'accountId', ${row}.${s("account")}, 'steps', ${row}.${s("steps")}, 'version', ${row}.${s("version")}, 'createdBy', ${row}.${s("createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`,
    memberRecord: (type, summary, step = "null::text", reason = "null::text") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', v_member.${r("tenant")}, 'id', v_member.${r("enrollment")}, 'sequenceId', v_member.${r("sequence")}, 'subjectType', v_member.${r("subjectType")}, 'subjectId', v_member.${r("subjectId")}, 'status', v_member.${r("status")}, 'step', ${step}, 'reason', ${reason})`,
        subject: `'sequence-enrollments/' || v_member.${r("enrollment")}::text`,
        tenant: `v_member.${r("tenant")}`,
        audit:
          summary === false
            ? false
            : {
                category: "data",
                targetType: "sequence",
                recordId: `v_member.${r("sequence")}::text`,
                targetLabel: `v_member.${r("subjectType")} || ':' || v_member.${r("subjectId")}`,
                summary: `'${summary}'`,
              },
      }),
  };
}
