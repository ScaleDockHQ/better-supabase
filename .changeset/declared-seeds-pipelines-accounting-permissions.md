---
"better-supabase": minor
---

`pipelines`, `accounting` and `permissions` declare their defaults. `pipelines` declares the default pipeline and stage template of every record type without a `scope` as `seed_pipelines_defaults`, with the named variants `b2b-sales` (deals) and `recruiting` (applications) that a binding picks through `on.<type>.variant`; `default_pipeline()` keeps its name and signature and applies the declared defaults on first use, and scoped bindings are still created on first use. `accounting` declares its dimensions, the `generic` chart (also the default) and a new `nl-rgs` Dutch chart with its account roles and journals as `seed_accounting_defaults`; `setup_accounting` calls it for an organization with no accounts. The `permissions` data step adds the catalog roles `owner`, `admin` and `member` when the roles table lacks them. `SeedTable` gains `defaultVariant`, and a seed reference can match a null column.
