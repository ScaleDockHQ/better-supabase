---
"better-supabase": minor
---

Pages the status-list blocks by the block list contract (ADR 1077). `collections`
gains `collectionPage`, `collectionFacets`, `collectionCount` and `get`, and
`reviews` gains `reviewPage`, `reviewFacets`, `reviewCount` and `get`, with sorts,
list filters and `q` over names, descriptions, titles and bodies. `leases`,
`passes`, `warranty`, `guests` and `agent-checkout` (sessions and mandates)
accept `q` on their pages. The SQL adds `page_collections`, `get_collection`,
`page_reviews` and `get_review`, and extends the leases, passes, warranty,
guests and agent-checkout list functions with a search filter, so the generated
schema files need `better-supabase upgrade`. The array methods
`collections.list`, `reviews.list`, `assets.assets`, `leases.list`,
`passes.list`, `warranty.list`, `guests.list`, `agentCheckout.listSessions` and
`agentCheckout.listMandates` keep working and are deprecated.

| Old                          | New                          |
| ---------------------------- | ---------------------------- |
| `collections.list`           | `collections.collectionPage` |
| `reviews.list`               | `reviews.reviewPage`         |
| `assets.assets`              | `assets.page`                |
| `leases.list`                | `leases.leasePage`           |
| `passes.list`                | `passes.passPage`            |
| `warranty.list`              | `warranty.page`              |
| `guests.list`                | `guests.page`                |
| `agentCheckout.listSessions` | `agentCheckout.sessionPage`  |
| `agentCheckout.listMandates` | `agentCheckout.mandatePage`  |
