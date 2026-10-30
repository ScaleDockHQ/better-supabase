import type { BlockOf } from "../define-block.ts";
import type { ConsentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createConsents } from "./consents.ts";
import { consentsEvents } from "./events.ts";
import { consentPurposeInputSchema } from "./schemas.ts";

/** The `consents` block's manifest (ADR 0029). */
export const consentsBlock: BlockOf<
  "consents",
  typeof createConsents,
  ConsentsEvents
> = defineBlock({
  name: "consents",
  sql: ["consents"],
  events: consentsEvents,
  schemas: { consent_purpose: { input: consentPurposeInputSchema } },
  create: createConsents,
  category: "admin",
  recipes: ["consent-register"],
  schedules: [
    {
      name: "expire",
      cron: "0 3 * * *",
      runs: "expire()",
      description: "Marks the grants past their valid-until date expired.",
    },
  ],
});
