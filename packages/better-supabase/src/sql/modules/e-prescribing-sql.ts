import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The SQL pieces the e-prescribing files share. */
export interface PrescribingSql {
  readonly fn: (name: string) => string;
  /** A column of the prescriptions table. */
  readonly p: (column: string) => string;
  readonly prescriptions: string;
  readonly read: string;
  readonly write: string;
  readonly sign: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly status: (message: string) => string;
  readonly missing: string;
  /** The medications block's context; the block requires it. */
  readonly medications: BlockSqlContext;
  readonly json: (row: string) => string;
  /** Records a `prescription.*` event of a prescriptions row. */
  readonly record: (type: string, row: string, summary: string) => string;
}

export function prescribingSql(ctx: BlockSqlContext): PrescribingSql {
  const p = (column: string): string => ctx.col("prescriptions", column);

  return {
    fn: (name) => ctx.fn(name),
    p,
    prescriptions: ctx.table("prescriptions"),
    read: ctx.permission("read", OPERATIONS["e-prescribing.read"]),
    write: ctx.permission("write", OPERATIONS["e-prescribing.write"]),
    sign: ctx.permission("sign", OPERATIONS["e-prescribing.sign"]),
    manage: ctx.permission("manage", OPERATIONS["e-prescribing.manage"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("PRESCRIPTION_INVALID", message, "22023"),
    forbidden: (message) => fail("PRESCRIPTION_FORBIDDEN", message),
    status: (message) => fail("PRESCRIPTION_STATUS", message, "55000"),
    missing: fail("PRESCRIPTION_NOT_FOUND", "no such prescription", "P0002"),
    medications: ctx.of("medications"),
    json: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'orderId', ${row}.${p("order")}, 'subjectType', ${row}.${p("subjectType")}, 'subjectId', ${row}.${p("subjectId")}, 'prescriberId', ${row}.${p("prescriber")}, 'prescriberName', ${row}.${p("prescriberName")}, 'status', ${row}.${p("status")}, 'order', ${row}.${p("snapshot")}, 'signedBy', ${row}.${p("signedBy")}, 'signedAt', ${row}.${p("signedAt")}, 'gateway', ${row}.${p("gateway")}, 'gatewayReference', ${row}.${p("gatewayReference")}, 'sentAt', ${row}.${p("sentAt")}, 'deliveryError', ${row}.${p("deliveryError")}, 'dispensedAt', ${row}.${p("dispensedAt")}, 'cancelledAt', ${row}.${p("cancelledAt")}, 'cancelReason', ${row}.${p("cancelReason")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`,
    record: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'orderId', ${row}.${p("order")}, 'subjectType', ${row}.${p("subjectType")}, 'subjectId', ${row}.${p("subjectId")}, 'status', ${row}.${p("status")})`,
        subject: `'prescriptions/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "prescription",
          recordId: `${row}.${p("id")}::text`,
          targetLabel: `${row}.${p("status")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
