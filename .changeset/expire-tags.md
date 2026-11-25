---
"better-supabase": minor
---

Add `bsb.expireTags(tags)`, which expires tags in Next's cache (`updateTag` in a
Server Action, `revalidateTag` in a Route Handler) and in the `bsb.kept()`
store, and resolves once the store has them. Doctor gains BS648 (`updateTag` or
`revalidateTag` beside `bsb.kept`) and BS649 (`refresh()` that expires nothing
beside `bsb.kept`), and `better-supabase codemod expire-tags` lists the calls to
change.
