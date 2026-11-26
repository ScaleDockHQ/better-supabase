---
"better-supabase": minor
---

`bsb.blockAction` takes a fourth argument that maps the data of a success, as
the third argument of `bsb.action` does, so a block action can answer with
`{ id }` and not the whole row. `tags` still receives the method's own data.
The Next.js example moves 171 single-call actions to `bsb.blockAction`.
