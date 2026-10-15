import type { BlockOf } from "../define-block.ts";
import type { AuditEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAuditLog } from "./client.ts";
import { auditEvents } from "./events.ts";

/** The `audit` block's manifest (ADR 0029). */
export const auditBlock: BlockOf<"audit", typeof createAuditLog, AuditEvents> =
  defineBlock({
    name: "audit",
    sql: ["audit"],
    options: {
      audit: optionKeys([
        "appendOnly",
        "correlationIdHeader",
        "eventCategory",
        "eventRoles",
        "trustedRoles",
        "eventSource",
        "exempt",
        "impersonators",
        "keepMappedMetadata",
        "metadataColumns",
        "readPolicy",
        "requestIdHeader",
        "restricted",
        "tenantColumn",
        "tenantLabel",
        "tenantLabelKey",
        "values",
      ]),
    },
    events: auditEvents,
    create: createAuditLog,
    category: "operations",
    recipes: ["audit-log-table"],
  });
