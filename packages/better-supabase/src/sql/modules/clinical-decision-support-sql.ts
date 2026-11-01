import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** A block context of another module, when it is installed and not custom. */
function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The SQL pieces the clinical-decision-support files share. */
export interface DecisionSupportSql {
  readonly fn: (name: string) => string;
  /** A column of the rules table. */
  readonly r: (column: string) => string;
  /** A column of the alerts table. */
  readonly a: (column: string) => string;
  readonly rules: string;
  readonly alerts: string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  /**
   * Refuses a record that isn't in the tenant, unless the caller is the
   * service.
   */
  readonly subjectCheck: (
    type: string,
    id: string,
    tenant: string,
    name: string,
  ) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly alertMissing: string;
  readonly ruleMissing: string;
  /** The medications block's context; the block requires it. */
  readonly medications: BlockSqlContext;
  readonly observations: BlockSqlContext | undefined;
  readonly consents: BlockSqlContext | undefined;
  readonly carePlans: BlockSqlContext | undefined;
  readonly ruleJson: (row: string) => string;
  readonly alertJson: (row: string) => string;
  /** Records a `care_alert.*` event of an alerts row. */
  readonly recordAlert: (type: string, row: string, summary: string) => string;
  /** Records a `care_rule.*` event of a rules row. */
  readonly recordRule: (type: string, row: string, summary: string) => string;
}

export function decisionSupportSql(ctx: BlockSqlContext): DecisionSupportSql {
  const r = (column: string): string => ctx.col("rules", column);
  const a = (column: string): string => ctx.col("alerts", column);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  return {
    fn: (name) => ctx.fn(name),
    r,
    a,
    rules: ctx.table("rules"),
    alerts: ctx.table("alerts"),
    read: ctx.permission("read", OPERATIONS["clinical-decision-support.read"]),
    write: ctx.permission(
      "write",
      OPERATIONS["clinical-decision-support.write"],
    ),
    manage: ctx.permission(
      "manage",
      OPERATIONS["clinical-decision-support.manage"],
    ),
    allowed,
    subjectCheck: (type, id, tenant, name) =>
      `if not (${SERVICE_CALLER} or ${subjectInTenant(ctx, type, id, tenant)}) then
    ${fail("CARE_ALERT_SUBJECT_INVALID", `${name} needs a record of the organization`, "22023")}
  end if;`,
    invalid: (message) => fail("CARE_ALERT_INVALID", message, "22023"),
    forbidden: (message) => fail("CARE_ALERT_FORBIDDEN", message),
    alertMissing: fail("CARE_ALERT_NOT_FOUND", "no such alert", "P0002"),
    ruleMissing: fail("CARE_RULE_NOT_FOUND", "no such rule", "P0002"),
    medications: ctx.of("medications"),
    observations: linked(ctx, "observations"),
    consents: linked(ctx, "consents"),
    carePlans: linked(ctx, "care-plans"),
    ruleJson: (row) =>
      `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'kind', ${row}.${r("kind")}, 'medicationIds', to_jsonb(${row}.${r("medicationIds")}), 'minDose', ${row}.${r("minDose")}, 'maxDose', ${row}.${r("maxDose")}, 'maxPerDay', ${row}.${r("maxPerDay")}, 'severity', ${row}.${r("severity")}, 'message', ${row}.${r("message")}, 'active', ${row}.${r("active")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")})`,
    alertJson: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'subjectType', ${row}.${a("subjectType")}, 'subjectId', ${row}.${a("subjectId")}, 'kind', ${row}.${a("kind")}, 'severity', ${row}.${a("severity")}, 'source', ${row}.${a("source")}, 'ruleId', ${row}.${a("rule")}, 'orderIds', to_jsonb(${row}.${a("orderIds")}), 'message', ${row}.${a("message")}, 'details', ${row}.${a("details")}, 'fingerprint', ${row}.${a("fingerprint")}, 'status', ${row}.${a("status")}, 'decidedBy', ${row}.${a("decidedBy")}, 'decidedAt', ${row}.${a("decidedAt")}, 'decisionReason', ${row}.${a("decisionReason")}, 'createdAt', ${row}.${a("createdAt")}, 'updatedAt', ${row}.${a("updatedAt")})`,
    recordAlert: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${a("tenant")}, 'id', ${row}.${a("id")}, 'subjectType', ${row}.${a("subjectType")}, 'subjectId', ${row}.${a("subjectId")}, 'kind', ${row}.${a("kind")}, 'severity', ${row}.${a("severity")}, 'source', ${row}.${a("source")}, 'status', ${row}.${a("status")})`,
        subject: `'care-alerts/' || ${row}.${a("id")}::text`,
        tenant: `${row}.${a("tenant")}`,
        audit: {
          category: "data",
          targetType: "care_alert",
          recordId: `${row}.${a("id")}::text`,
          targetLabel: `${row}.${a("kind")}`,
          summary: sqlString(summary),
        },
      }),
    recordRule: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}, 'id', ${row}.${r("id")}, 'kind', ${row}.${r("kind")}, 'severity', ${row}.${r("severity")})`,
        subject: `'care-rules/' || ${row}.${r("id")}::text`,
        tenant: `${row}.${r("tenant")}`,
        audit: {
          category: "configuration",
          targetType: "care_rule",
          recordId: `${row}.${r("id")}::text`,
          targetLabel: `${row}.${r("kind")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
