---
"better-supabase": minor
---

Two small additions. The generated module exports `WhereOf<"table">`, a `where` with writable keys for filters you build one condition at a time, and `better-supabase` exports its generic form, `MutableWhere<Models, T>`; `WhereInput`, `FindManyArgs` and `OrderByArg` were already exported. Connected buckets from `better-supabase/storage` have `copy(from, to)` and `move(from, to)`, which copy or move an object within the bucket in one Storage request after checking both paths against the template and the tenant, and return the new path. Regenerate with `better-supabase gen` to get `WhereOf`.
