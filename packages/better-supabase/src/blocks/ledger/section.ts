import type { Section } from "../sections.ts";
import type { Ledger, LedgerAccount } from "./ledger.ts";

import { defineSection } from "../sections.ts";

/** A record's ledger accounts with their balances: credits, points, stock. */
export const ledgerSection: Section<Ledger, readonly LedgerAccount[]> =
  defineSection({
    permissions: { read: "read", write: "post" },
    module: "ledger",
    load: (client: Ledger, subject) => client.holderAccounts(subject),
    events: ["ledger_transaction.*", "ledger_account.*", "ledger_hold.*"],
  });
