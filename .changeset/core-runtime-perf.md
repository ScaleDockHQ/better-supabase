---
"better-supabase": minor
---

List queries count with `count: "planned"` by default, so a large table no longer pays for an exact count on every page; pass `count: "exact"` to keep the old behavior. Keyset pagination on two or more columns adds a range bound on the first column so Postgres can use its index. Chunked `in` reads dedupe their values and run up to four chunks at once. The outbox relays to its consumers concurrently, notifications deliver to their channels concurrently, and usage reporting looks up customers and sends meter events eight at a time. Repeated reads reuse their compiled selection and plugin lists.
