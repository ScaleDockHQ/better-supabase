---
"better-supabase": minor
---

Named presets can start from seed variants, a Create design can carry seeds, and doctor checks them.

- `crm` seeds the `b2b-sales` variant of `pipelines`, `ats` the `recruiting` variant, and `erp` the `generic` chart of `accounting`. `expandPreset` writes them under `database.seed.defaults.variants`, and the app's own variants and locale win.
- Design format 9 `seeds` takes `sample: { size, seed }` next to `variants` and `locale`. `init --preset` and `add --preset` write all of it to the config, and `schemas/design-v1.json` describes it.
- New doctor checks: BS354 (declared defaults that new organizations don't receive), BS355 (a configured variant the block doesn't declare) and BS356 (a generated sample file outside `database.seed.sample.output`).
