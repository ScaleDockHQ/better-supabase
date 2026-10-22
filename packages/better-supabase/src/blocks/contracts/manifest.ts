import type { BlockOf } from "../define-block.ts";
import type { ContractsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createContracts } from "./contracts.ts";
import { contractsEvents } from "./events.ts";
import { contractsSqlOptions } from "./options.ts";
import {
  contractChangesSchema,
  contractInputSchema,
  obligationInputSchema,
} from "./schemas.ts";
import { contractsSection } from "./section.ts";

/** The `contracts` block's manifest (ADR 0029). */
export const contractsBlock: BlockOf<
  "contracts",
  typeof createContracts,
  ContractsEvents,
  Record<never, never>,
  never,
  { readonly contracts: typeof contractsSection }
> = defineBlock({
  name: "contracts",
  sql: ["contracts"],
  options: { contracts: contractsSqlOptions },
  events: contractsEvents,
  schemas: {
    contract: { input: contractInputSchema, change: contractChangesSchema },
    obligation: { input: obligationInputSchema },
  },
  create: createContracts,
  sections: { contracts: contractsSection },
  recipes: ["contract-renewals"],
  category: "crm",
});
