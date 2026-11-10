---
"better-supabase": minor
---

`gen.constants: true` writes `enums.ts` and `columns.ts` next to the generated module. `enums.ts` holds every enum and CHECK value list as a constant array and a union type, and `columns.ts` maps each column's row name to its database name for every table. Neither imports anything, so a browser form or a script uses them without the runtime package.
