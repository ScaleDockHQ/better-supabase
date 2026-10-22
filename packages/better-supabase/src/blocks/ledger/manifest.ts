import type { BlockOf } from "../define-block.ts";
import type { LedgerEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { ledgerEvents } from "./events.ts";
import { createLedger } from "./ledger.ts";
import { ledgerSection } from "./section.ts";

/** The `ledger` block's manifest (ADR 0029). */
export const ledgerBlock: BlockOf<
  "ledger",
  typeof createLedger,
  LedgerEvents,
  Record<never, never>,
  never,
  { readonly ledger: typeof ledgerSection }
> = defineBlock({
  name: "ledger",
  sql: ["ledger"],
  options: {},
  events: ledgerEvents,
  create: createLedger,
  sections: { ledger: ledgerSection },
  category: "commerce",
});
