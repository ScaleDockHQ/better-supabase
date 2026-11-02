---
"better-supabase": minor
---

The composite blocks gain helpers that chain their parts. `crm` adds `route`, which picks an owner
from the assignment queues using the record's segments, and `attainment`, which sums target
progress per metric and lists the targets behind the period's pace. `saas` adds `rotateApiKey`
with a grace period in hours, and `better-supabase/blocks/saas` exports `createKeyRotator` for
apps that do not install every part. `support` adds `escalate`, `commerce` adds `processReturn`
with restock, quarantine and reject dispositions and an optional refund, and `projects` adds
`utilization`, `financials` and `retainerDrawdown`.
