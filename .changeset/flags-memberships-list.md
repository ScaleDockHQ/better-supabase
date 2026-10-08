---
"better-supabase": minor
---

`flagContext` reads a `memberships` claim that is a list of `{ scope, id, roles }` entries, from the root scope's entry for the tenant or from `membershipScope`, next to the `tenant` module's object of tenant id to role. A caller with several roles gets them all as `roles`, and a flag rule's `roles` list matches any of them. The `roles` option reads roles from claims of any other shape.
