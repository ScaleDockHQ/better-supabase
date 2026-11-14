---
"better-supabase": minor
---

Mark which block events are public. `event<T>({ public: true })` records the
event in `Events.public`, and `webhookEventCatalog(blocks)` from
`better-supabase/blocks` lists them by block, so an app offers webhook
subscribers only those. `organizations`, `shipments`, `invoices` and `orders`
mark their events. The manifests of the blocks that `powersync streams`
supports now declare `offline: true` on their entity. Nothing changes for an
app that ignores both.
