---
"better-supabase": minor
---

Add the `better-supabase/generators/tags` generator, which writes `<output>.tags.ts` with a `defineTags` call over the schema's tables.

| Before                                          | After                                                 |
| ----------------------------------------------- | ----------------------------------------------------- |
| `defineTags(["customers", "invoices"])` by hand | `gen: { generators: [tags()] }` and `import { tags }` |
