---
"better-supabase": minor
---

`paginate` accepts an offset window: `paginate({ offset, limit, count: 'exact' })` returns the same page shape as `page` and `size`, with the rows and the total in one request. A counted page whose offset is past the last row now returns no items and the total over PostgREST too, instead of a 416 error.
