---
"better-supabase": minor
---

Next.js cache tags can be scoped to a tenant. `bs.cacheTag(table, id, { tenant })` and `bs.cacheTags(specs, { tenant })` tag a read `bs:<table>@<tenant>` and `bs:<table>@*` instead of `bs:<table>`, and `nextCache()` invalidates `bs:<table>`, the mutation's tenant tag (`bs:<table>@*` when the mutation has no tenant) and the row tags. A mutation in one tenant no longer revalidates cached reads of every other tenant. `tagFor(table, undefined, { tenant })` builds the tag, and `TagOptions` types the option. Reads tagged without a tenant behave as before.
