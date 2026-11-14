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
  entities: {
    consent: {
      mutability: "state-machine",
      emits: { create: false },
      personalData: ["givenByUser", "withdrawnReason", "signature"],
      subjectColumn: "subjectId",
      erase: "anonymize",
      legalHold: true,
    },
    consent_signal: {
      mutability: "read-only",
      personalData: ["raw", "parsed"],
      subjectColumn: "subjectId",
      erase: "delete",
    },
    consent_purpose: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Consent per record and purpose: the purposes an organization asks consent for with their lawful basis and version, each decision with who made it (the person or a representative) and its signature, form or file as evidence, withdrawals and expiry. consent_active() answers whether processing may go ahead.",
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
