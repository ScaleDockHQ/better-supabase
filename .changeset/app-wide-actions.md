---
"better-supabase": minor
---

Add `createNext({ actions: { envelope, guard, from } })` for rules every `bsb.action` shares, `ActionDefaultsProvider` in `better-supabase/react` for app-wide `onSuccess` and `onError` of `useAction`, `useOptimisticAction` and `useActionForm`, and `defineTags(tables)` for tags a reader and an action declare once.

| Before                                         | After                                                          |
| ---------------------------------------------- | -------------------------------------------------------------- |
| a wrapper around `bsb.action` for the envelope | `createNext(bs, { actions: { envelope } })`                    |
| the same toast in every `useAction` call       | `<ActionDefaultsProvider value={{ onError }}>`                 |
| a hand-written `*-cache.ts` tag helper         | `const tags = defineTags(["customers"])`; `tags.customers(id)` |
