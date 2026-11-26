---
"better-supabase": minor
---

Add the `domains` option to the `tags()` generator, so feature tags such as `crm` are declared once next to the table tags.

| Before                                 | After                                      |
| -------------------------------------- | ------------------------------------------ |
| `export const CRM_TAG = tagFor("crm")` | `tags({ domains: ["crm"] })`, `tags.crm()` |
