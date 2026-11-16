---
"better-supabase": minor
---

`dispatch` and `shipments` get `getOrNotFound(id)`, which returns the row or a
`not_found` error (`DISPATCH_NOT_FOUND`, `SHIPMENT_NOT_FOUND`) as the block
list contract asks (ADR 1077). `get(id)` keeps returning `null` for a missing
row, so apiVersion 1 does not change, and is marked `@deprecated`.

| Before                       | After                         |
| ---------------------------- | ----------------------------- |
| `dispatch.get(id)` (`null`)  | `dispatch.getOrNotFound(id)`  |
| `shipments.get(id)` (`null`) | `shipments.getOrNotFound(id)` |
