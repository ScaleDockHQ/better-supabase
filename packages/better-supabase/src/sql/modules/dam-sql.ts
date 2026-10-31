import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The SQL pieces the dam files share. */
export interface DamSql {
  readonly fn: (name: string) => string;
  /** A column of the renditions table. */
  readonly n: (column: string) => string;
  /** A column of the usage rights table. */
  readonly u: (column: string) => string;
  readonly renditions: string;
  readonly rights: string;
  readonly subject: string;
  readonly read: string;
  readonly write: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly rightMissing: string;
  readonly renditionJson: (row: string) => string;
  /** The status of a usage right on a day, as SQL over a rights row. */
  readonly rightStatus: (row: string, day: string) => string;
  readonly rightJson: (row: string) => string;
  /** Records a `dam_usage_right.*` event of a rights row. */
  readonly recordRight: (type: string, row: string, summary: string) => string;
}

export function damSql(ctx: BlockSqlContext): DamSql {
  const n = (column: string): string => ctx.col("renditions", column);
  const u = (column: string): string => ctx.col("rights", column);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const rightStatus = (row: string, day: string): string =>
    `case when ${row}.${u("revokedAt")} is not null then 'revoked' when ${row}.${u("startsOn")} > ${day} then 'upcoming' when ${row}.${u("expiresOn")} is not null and ${row}.${u("expiresOn")} < ${day} then 'expired' else 'active' end`;

  return {
    fn: (name) => ctx.fn(name),
    n,
    u,
    renditions: ctx.table("renditions"),
    rights: ctx.table("rights"),
    subject: sqlString(ctx.naming.rename("dam_usage_right")),
    read: ctx.permission("read", OPERATIONS["dam.read"]),
    write: ctx.permission("write", OPERATIONS["dam.write"]),
    allowed,
    invalid: (message) => fail("DAM_INVALID", message, "22023"),
    forbidden: (message) => fail("DAM_FORBIDDEN", message),
    rightMissing: fail(
      "DAM_USAGE_RIGHT_NOT_FOUND",
      "no such usage right",
      "P0002",
    ),
    renditionJson: (row) =>
      `jsonb_build_object('id', ${row}.${n("id")}, 'organizationId', ${row}.${n("tenant")}, 'nodeId', ${row}.${n("node")}, 'kind', ${row}.${n("kind")}, 'status', ${row}.${n("status")}, 'format', ${row}.${n("format")}, 'width', ${row}.${n("width")}, 'height', ${row}.${n("height")}, 'sizeBytes', ${row}.${n("sizeBytes")}, 'path', ${row}.${n("path")}, 'error', ${row}.${n("error")}, 'createdAt', ${row}.${n("createdAt")}, 'updatedAt', ${row}.${n("updatedAt")})`,
    rightStatus,
    rightJson: (row) =>
      `jsonb_build_object('id', ${row}.${u("id")}, 'organizationId', ${row}.${u("tenant")}, 'nodeId', ${row}.${u("node")}, 'licensee', ${row}.${u("licensee")}, 'territory', ${row}.${u("territory")}, 'channel', ${row}.${u("channel")}, 'startsOn', ${row}.${u("startsOn")}, 'expiresOn', ${row}.${u("expiresOn")}, 'status', ${rightStatus(row, "current_date")}, 'note', ${row}.${u("note")}, 'revokedAt', ${row}.${u("revokedAt")}, 'createdBy', ${row}.${u("createdBy")}, 'createdAt', ${row}.${u("createdAt")})`,
    recordRight: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${u("tenant")}, 'id', ${row}.${u("id")}, 'nodeId', ${row}.${u("node")}, 'licensee', ${row}.${u("licensee")}, 'expiresOn', ${row}.${u("expiresOn")})`,
        subject: `'dam-usage-rights/' || ${row}.${u("id")}::text`,
        tenant: `${row}.${u("tenant")}`,
        audit: {
          category: "data",
          targetType: "dam_usage_right",
          recordId: `${row}.${u("id")}::text`,
          targetLabel: `${row}.${u("licensee")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
