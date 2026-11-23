---
"better-supabase": patch
---

The schema reader now treats a policy without a `to` clause, or with `to public`, as a policy for `public`, so the grants it derives match the text scanner. A column `references ... deferrable` is read as deferrable, and `comment on function` keeps its argument signature.
