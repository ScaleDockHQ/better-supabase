import type { BlockOf } from "../define-block.ts";
import type { ServiceAccountsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { serviceAccountsEvents } from "./events.ts";
import { serviceAccountsSqlOptions } from "./options.ts";
import { createServiceAccounts } from "./service-accounts.ts";

/** The `service-accounts` block's manifest (ADR 0029). */
export const serviceAccountsBlock: BlockOf<
  "service-accounts",
  typeof createServiceAccounts,
  ServiceAccountsEvents
> = defineBlock({
  name: "service-accounts",
  sql: ["service-accounts"],
  options: { "service-accounts": serviceAccountsSqlOptions },
  events: serviceAccountsEvents,
  create: createServiceAccounts,
  category: "developer",
  recipes: ["service-accounts-table"],
});
