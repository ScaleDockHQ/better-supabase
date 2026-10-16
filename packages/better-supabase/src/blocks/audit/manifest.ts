import type { BlockOf } from "../define-block.ts";
import type { AuditEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { auditEvents } from "./events.ts";
import { createAuditLog } from "./log.ts";
import { auditSqlOptions } from "./options.ts";

/** The `audit` block's manifest (ADR 0029). */
export const auditBlock: BlockOf<"audit", typeof createAuditLog, AuditEvents> =
  defineBlock({
    name: "audit",
    sql: ["audit"],
    options: {
      audit: auditSqlOptions,
    },
    events: auditEvents,
    create: createAuditLog,
    category: "operations",
    recipes: ["audit-log-table"],
  });
