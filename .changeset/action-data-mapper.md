---
"better-supabase": minor
---

`bsb.action(options, fn, map)` takes a third argument that maps the data of a successful call to another type, so `ActionResult<Row>` can become `ActionResult<ViewModel>`. The mapper may be async, runs after the `invalidates` tags drop and turns a thrown `DbException` into the action's error. `ActionMapper` is exported from `better-supabase/next`.
