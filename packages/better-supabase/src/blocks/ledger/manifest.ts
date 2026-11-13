import type { BlockOf } from "../define-block.ts";
import type { LedgerEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { ledgerEvents } from "./events.ts";
import { createLedger } from "./ledger.ts";
import { ledgerBinding } from "./record-binding.ts";

/** The `ledger` block's manifest (ADR 0029). */
export const ledgerBlock: BlockOf<
  "ledger",
  typeof createLedger,
  LedgerEvents,
  Record<never, never>,
  never,
  typeof ledgerBinding
> = defineBlock({
  name: "ledger",
  sql: ["ledger"],
  options: {},
  events: ledgerEvents,
  create: createLedger,
  record: ledgerBinding,
  category: "commerce",
  entities: {
    ledger_account: { mutability: "state-machine", emits: { create: false } },
    ledger_transaction: { mutability: "state-machine" },
    ledger_hold: { mutability: "state-machine" },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Double-entry accounts in a currency or a custom unit, balanced transactions, balances and holds. Credits, stock, leave balances and invoice payments post through it.",
});
