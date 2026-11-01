import type { RecordBinding } from "../record-bindings.ts";
import type { Ledger, LedgerAccount } from "./ledger.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A record's ledger accounts with their balances: credits, points, stock. */
export const ledgerBinding: RecordBinding<Ledger, readonly LedgerAccount[]> =
  defineRecordBinding({
    permissions: { read: "read", write: "post" },
    module: "ledger",
    load: (client: Ledger, subject) =>
      client.holderAccounts({ holder: subject }),
    events: ["ledger_transaction.*", "ledger_account.*", "ledger_hold.*"],
  });
