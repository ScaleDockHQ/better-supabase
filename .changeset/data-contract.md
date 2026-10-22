---
"better-supabase": minor
---

Repositories and block clients share one data contract. Reads are `list`, `page`, `get`, `count` and `aggregate`; writes are `create`, `update`, `upsert` and `delete`; `attach` and `detach` link a row to a record. `findMany`, `findFirst`, `findOnly`, `findUnique`, `findById`, `paginate`, `exists` and the `*Many` methods go: `get` takes a primary key, a unique key or `{ where }` (with `{ optional: true }` for null), `create` and `upsert` take one row or an array, and `update` and `delete` take a key or `{ where }`.

Block clients move to the same verbs. `tags.tag` and `untag` become `attach` and `detach`, `tags.create`, `update` and `list` take objects, `forSubject(record)` on tags, channels and scores becomes `list({ on: record })`, and `save` on the block clients and `set` on ai-cache and ai-files `providerFiles` become `upsert`. The lint rules `no-unbounded-find-many` and `no-delete-many-without-where` become `no-unbounded-list` and `no-empty-where`, and the guards `noUnboundedFindMany` and `noDeleteManyWithoutWhere` become `noUnboundedList` and `noDeleteWithoutWhere`.

Run `better-supabase codemod 0.15` to rewrite the repository calls, the guard options and the lint rule names. It lists the block client calls to review.
