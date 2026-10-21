---
"better-supabase": minor
---

`codemod 0.9` now pins `defaultFormat: "standard"` on an adopted
`webhooks-out` block that maps no `columns.endpoints.format` and sets no
`defaultFormat`, which keeps the 0.8 body, and lists `sql add` calls in
scripts and workflows for review (`add` also wires clients). A new
`codemod 0.11` pins `defaultFormat: "cloudevents"` under the same conditions,
since adopt mode requires the key from 0.11. Both list the edit for review.
