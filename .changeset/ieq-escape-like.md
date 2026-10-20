---
"better-supabase": minor
---

Add the `ieq` filter operator for case-insensitive equality, on text columns and jsonb `path` filters. It sends `ilike` with `%`, `_` and `\` escaped, so `where: { email: { ieq: input } }` matches only that address in any case.

Add the `require-escape-like` rule to `better-supabase/lint`, on as a warning in `configs.recommended`. It flags a `like` or `ilike` value taken from a variable, a property, or a template or concatenation without `escapeLike(...)`.
