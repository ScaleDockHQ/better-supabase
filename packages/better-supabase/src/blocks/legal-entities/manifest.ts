import type { BlockOf } from "../define-block.ts";
import type { LegalEntitiesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { legalEntitiesEvents } from "./events.ts";
import { createLegalEntities } from "./legal-entities.ts";
import { legalEntityListSurface } from "./lists.ts";
import { legalEntitiesSqlOptions } from "./options.ts";
import { legalEntityInputSchema } from "./schemas.ts";

/** The `legal-entities` block's manifest (ADR 0029, ADR 0142). */
export const legalEntitiesBlock: BlockOf<
  "legal-entities",
  typeof createLegalEntities,
  LegalEntitiesEvents
> = defineBlock({
  name: "legal-entities",
  sql: ["legal-entities"],
  options: { "legal-entities": legalEntitiesSqlOptions },
  events: legalEntitiesEvents,
  schemas: { legal_entity: { input: legalEntityInputSchema } },
  create: createLegalEntities,
  category: "tenancy",
  entities: {
    legal_entity: {
      ...legalEntityListSurface,
      mutability: "editable",
      emits: { create: true, update: true },
    },
    legal_entity_setting: { mutability: "editable", emits: { update: false } },
  },
  concerns: ["lifecycle"],
  description:
    "Several legal entities inside one organization, each with its VAT and chamber numbers, bank account, logo and fiscal settings and one default per organization. Settings resolve from the legal entity to the organization to the code default, and options.on adds a nullable legal_entity_id to invoices, quotes, orders, numbering, accounting, inventory locations and settings; null means the default entity.",
});
