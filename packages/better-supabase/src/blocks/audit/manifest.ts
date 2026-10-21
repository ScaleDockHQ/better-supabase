import type { BlockOf } from "../define-block.ts";
import type { AuditEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAudit } from "./audit-log.ts";
import { auditEvents } from "./events.ts";
import { auditSqlOptions } from "./options.ts";

/** The `audit` block's manifest (ADR 0029). */
export const auditBlock: BlockOf<"audit", typeof createAudit, AuditEvents> =
  defineBlock({
    name: "audit",
    sql: ["audit"],
    options: { audit: auditSqlOptions },
    events: auditEvents,
    create: createAudit,
    category: "admin",
    recipes: ["audit-log-table"],
  });
