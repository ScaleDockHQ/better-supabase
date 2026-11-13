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
    entities: {
      audit: { mutability: "state-machine", emits: { create: false } },
    },
    description:
      "Records inserts, updates and deletes with the actor and changed columns for tables you register, plus semantic events through audit_event(), with redaction, an append-only guard, a tenant read policy and per-tenant retention as options.",
    recipes: ["audit-log-table"],
  });
