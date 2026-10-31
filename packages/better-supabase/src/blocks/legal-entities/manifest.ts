import type { BlockOf } from "../define-block.ts";
import type { LegalEntitiesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { legalEntitiesEvents } from "./events.ts";
import { createLegalEntities } from "./legal-entities.ts";
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
});
