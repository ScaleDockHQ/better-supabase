---
"better-supabase": minor
---

`sql.modules.usage.options.meters` takes `{ table, key, unit, category, label, active }` to read the meter catalog from the app's own table instead of the config. `usage_meters()` and the unknown-meter check read the table on every call, so a meter added there counts right away.
