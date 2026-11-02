---
"better-supabase": minor
---

Nineteen composite blocks are available from `better-supabase/blocks/<name>`: `saas`, `sales`,
`crm`, `commerce`, `procurement`, `finance`, `support`, `projects`, `service`, `people`,
`recruiting`, `scheduling`, `learning`, `events`, `cms`, `care`, `filespace`, `collaboration` and
`governance`. Each lists the blocks it is made of, carries their defaults, and adds helpers where a
flow spans parts (`crm.closeWon`, `finance.closePeriod`, `filespace.put`, `recruiting.hire`).
`crm` also declares a named read set. The named presets now list composites, and each resolves to
the same set of modules as before, except that `helpdesk` also installs the Chat SDK state tables.
