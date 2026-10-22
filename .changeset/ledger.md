---
"better-supabase": minor
---

Add the `ledger` block: double-entry accounts, balanced transactions, running balances and holds. Inventory stock, leave balances and invoice payments move onto it (breaking for apps that read those tables directly).

- `better-supabase add ledger` installs accounts per organization in a currency (minor units, `Money`) or a custom unit, transactions whose entries sum to zero per unit, append-only entries corrected by `reverse`, and holds that are captured or released. `createLedger` from `better-supabase/blocks/ledger` opens accounts, posts and reads balances; `ledgerSection` shows a record's accounts on its page. Credits, loyalty points, gift cards and trust balances are account kinds.
- Inventory, leave and invoices require `ledger`. Their client methods and SQL functions keep their names and results; `sql upgrade` copies the old rows into ledger transactions with the same ids and drops the old tables.

| Before                                   | After                                                              |
| ---------------------------------------- | ------------------------------------------------------------------ |
| `stock_movements`                        | `ledger_transactions` of kind `stock.<reason>`                     |
| `leave_ledger`                           | `ledger_transactions` of kind `leave.<entry>`                      |
| `invoice_payments`                       | `ledger_transactions` of kind `invoice.payment` / `invoice.refund` |
| `blocks.<name>.tables` key for the above | removed; read the ledger instead                                   |

See the 0.13 to 0.14 upgrade guide.
