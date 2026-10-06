---
"better-supabase": minor
---

Filter by a key inside a jsonb column. `where: { metadata: { path: ["owner", "id"], eq: id } }` compares the text at that path (`metadata->owner->>id=eq.<id>` over PostgREST, `metadata #>> '{owner,id}'` over SQL) and takes `eq`, `neq`, `in`, `notIn`, `isNull`, `gt`, `gte`, `lt`, `lte`, `like` and `ilike`, also inside `OR`, `AND` and `NOT`. `isNull: true` matches a missing key and a JSON `null`. SQLite returns `unsupported`. The `JsonPathOps` type describes the operators. An equality filter whose value is an object with a `path` array is now read as a path filter.
