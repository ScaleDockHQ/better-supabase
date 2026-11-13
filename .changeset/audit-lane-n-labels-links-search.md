---
"better-supabase": minor
---

Subjects get labels, parties and declared composition. `subjects.label(refs)` returns a label for every subject (its title, or its id with `found: false`), batched by `batchSubjects`. `createPartyResolver` in `better-supabase/blocks/subjects` resolves a name, initials, an avatar URL and a page for any subject from `subjects.label` and one reader per subject type. `defineBlock` takes `links` (written with `blockLink`) and `concerns`, and every block that has SQL links or concerns declares them. A subject whose SQL module names no search registration now registers its title column, with the body columns of its manifest entity's `search`, and `blocks.<name>.names.<entity>.search` replaces the columns or turns it off with `false`. `Subjects` gains `label`, so a hand-written `Subjects` double adds it.

| Before                                                 | After                                                                        |
| ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| A subject reference has no text                        | `subjects.label([{ type, id }])`                                             |
| Pages join contacts, employees and profiles by hand    | `createPartyResolver({ label: subjects.label, readers })`                    |
| Links and concerns live in SQL `NAMES` only            | `defineBlock({ links: [blockLink(...)], concerns: ["search"] })`             |
| 17 subjects have no search registration                | Title column by default; `names.<entity>.search: { title, body }` or `false` |
| A custom `Subjects` object without `label` type-checks | Add `label`, for example `label: (refs) => labelsOf(resolve, refs)`          |
