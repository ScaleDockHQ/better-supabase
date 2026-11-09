---
"better-supabase": minor
---

An imported invoice, credit note, quote or order stays as imported unless `data.update` is `apply`. Apply writes the header and, when the line count is unchanged, the line title and tax. A different line count replaces the lines. A void or paid document keeps its postings unless `data.repost` is true.
