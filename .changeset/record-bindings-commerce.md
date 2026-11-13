---
"better-supabase": minor
---

The `invoices`, `quotes` and `deals` blocks have record bindings. `invoicesBinding`, `quotesBinding` and `dealsBinding` load the invoices, quotes or deals that name a record as their company or contact (a deal also by its contacts), read again on the block's events, and take the organization from the block's `tenant` option. Each block client gets `list({ subject, limit })` and a SQL function (`list_invoices_for_subject`, `list_quotes_for_subject`, `list_deals_for_subject`); run `better-supabase upgrade` and apply the new migration. The three options types accept `tenant`.

| Before                                                                               | After                                                            |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `invoicesBlock.record`, `quotesBlock.record` and `dealsBlock.record` are `undefined` | They are `invoicesBinding`, `quotesBinding` and `dealsBinding`   |
| Invoices, quotes and deals of a record read by hand                                  | `invoices.list`, `quotes.list` and `deals.list` with a `subject` |
