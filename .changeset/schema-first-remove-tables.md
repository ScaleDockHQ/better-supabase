---
"better-supabase": minor
---

Breaking: the config has no `tables` key, and `records` is now `subjects`. Tables are SQL files you own under `supabase/schemas`, with features as `@bsb` tags in the table comment. Run `better-supabase migrate schema-first` once to write the files from your old `tables`, then delete `tables` and rename `records` to `subjects`; every other command refuses the old keys and says so. `init --preset` and `add --preset` write a design's tables as SQL files and keep a file that exists, so the breaking-change report and rename statements of `add --preset` are gone (`db diff` plans them). `AppTableNames`, `TypedReference` and `hasFlatTables` are removed from `better-supabase/config`, and `presetConfigSource` returns a config without the design's tables. Create's design format and `better-supabase/create/lite` keep `appTables`. See the 0.27 to 0.28 migration guide.
