---
"better-supabase": minor
---

The `quotes` and `invoices` SQL modules and their blocks add the sales documents after a deal. A quote has lines and totals the database keeps and a revision chain. It is sent as a link the customer opens without an account and answers with accept, reject or changes requested, and it expires after its valid date. `quotes.fromDeal` makes one draft per deal. An invoice gets a gapless number when it is issued and collects payments (a payment reference is recorded once). Credit notes reduce its balance, and it can be voided, written off and aged per currency. `invoices.fromQuote` makes deposit invoices and one final invoice that subtracts them. With the relations module installed, both link to their origin with `created_from`.
