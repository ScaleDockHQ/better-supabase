---
"better-supabase": minor
---

The generated module exports `OrderTermOf<"table">`, one sort term of a table's `orderBy`, so a tiebreak or a sort list assembled from parts no longer needs `Exclude<OrderByOf<"table">, readonly unknown[]>`. Run `better-supabase gen` to get it; `OrderByInput<Models, T>` is the generic form.
