---
"better-supabase": minor
---

Blocks that attach to records take their record types from `on` on the block
entry instead of `options.subjects`, and `field-history` takes
`on: { <type>: { fields: [...] } }`. `better-supabase upgrade` moves the
value. A config that still sets `options.subjects` fails with the key to move,
and the new doctor check BS346 reports an `on` entry that `config.records`
doesn't register.
