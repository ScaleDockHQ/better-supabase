import type { BlockOf } from "../define-block.ts";
import type { ContractsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createContracts } from "./contracts.ts";
import { contractsEvents } from "./events.ts";
import { contractsSqlOptions } from "./options.ts";
import { contractsBinding } from "./record-binding.ts";
import {
  contractChangesSchema,
  contractInputSchema,
  obligationInputSchema,
} from "./schemas.ts";

/** The `contracts` block's manifest (ADR 0029). */
export const contractsBlock: BlockOf<
  "contracts",
  typeof createContracts,
  ContractsEvents,
  Record<never, never>,
  never,
  typeof contractsBinding
> = defineBlock({
  name: "contracts",
  sql: ["contracts"],
  options: { contracts: contractsSqlOptions },
  events: contractsEvents,
  schemas: {
    contract: { input: contractInputSchema, change: contractChangesSchema },
    contract_obligation: { input: obligationInputSchema },
  },
  create: createContracts,
  record: contractsBinding,
  recipes: ["contract-renewals"],
  category: "crm",
  entities: {
    contract: { mutability: "editable", emits: { create: true, update: true } },
    contract_obligation: {
      mutability: "editable",
      emits: { create: true, update: true, delete: false },
    },
  },
  description:
    "Contracts with counterparties from draft through review and signature to active, expired or terminated, built on signatures, versions and reminders. Values are bigint minor units; renewal terms (auto-renew, renewal period, notice days) schedule a reminder before the notice deadline; obligations carry due dates and owners.",
});
