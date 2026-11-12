import type { BlockOf } from "../define-block.ts";
import type { ServiceAccountsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { serviceAccountsEvents } from "./events.ts";
import { createServiceAccounts } from "./service-accounts.ts";

/** The `service-accounts` block's manifest (ADR 0029). */
export const serviceAccountsBlock: BlockOf<
  "service-accounts",
  typeof createServiceAccounts,
  ServiceAccountsEvents
> = defineBlock({
  name: "service-accounts",
  sql: ["service-accounts"],
  events: serviceAccountsEvents,
  create: createServiceAccounts,
  category: "developer",
  entities: {
    service_principal: { mutability: "state-machine", emits: { create: true } },
  },
  description:
    "Non-human tenant members backed by auth.users rows that can't sign in, with roles through memberships. Organization-owned workflow versions and service webhook endpoints run as the tenant's default principal.",
  recipes: ["service-accounts-table"],
});
