---
"better-supabase": minor
---

`gen` now also writes the columns, the detail frame and the forms of an entity
page. Set `columns` and `sections` on `defineEntityPage` and `gen` writes
`pages/<name>.columns.ts` (each column with its label, kind and the declared sort
and filter of the same name) and `pages/<name>.detail.ts` (the `/:id` route, the
sections and `href(id)`). A page whose block exports an input schema also gets
`pages/<name>.form.ts` with `<name>CreateForm` and `<name>EditForm`, built with
the new `defineEntityForm` from `better-supabase/list`, so a form cannot drift
from the action it submits to. `better-supabase/list` also exports the types
`EntityColumn`, `EntityDetail`, `EntityDetailSection`, `EntityFieldKind`,
`EntityForm`, `EntityFormField` and `EntityFormParse`. The descriptor keeps
`apiVersion: 1`.

The entity list helper type `ListArgs` is now `ListCallParams` and the eve type
`EveDynamicRunArgs` is `EveDynamicRunParams`, so neither uses the banned `Args`
suffix (ADR 0246).
