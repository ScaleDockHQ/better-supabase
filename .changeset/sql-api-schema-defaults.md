---
"better-supabase": minor
---

`sql.api` and `sql.schema` set the Data API schema and the module schema for every module that leaves its own unset, so a config no longer repeats `api: "api"` per module. A module's `api: false` keeps it out of the API schema when `sql.api` is set.
