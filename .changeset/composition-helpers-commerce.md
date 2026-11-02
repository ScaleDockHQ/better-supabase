---
"better-supabase": minor
---

Commerce and finance blocks gain helpers that replace chains of calls, each taking one object and
returning a Result. New: `pipelines.default` and `pipelines.ensure`, `quotes.draftFromDeal`,
`orders.markPaid`, `orders.returnAndRefund` and `orders.fulfilAll`, `invoices.createAndIssue`,
`invoices.markPaid` and `invoices.issueAndSend`, `banking.reviewQueue` and `banking.acceptBestMatch`,
`catalog.createSimpleProduct`, `shipments.shipCheapest`, `rfqs.awardBest`, `accounting.initialize`
and `accounting.yearToDate`, `expenses.file` and `promotions.createWithCode`.
