---
"better-supabase": minor
---

Config inference covers two more lines. The `notifications` block is installed when `gen.powersync.instances` or `gen.clientBlocks` names it, and `standardSchema({ settings: "./src/settings.ts#settings" })` gives the `settings` block its `defineSettings()` schemas, so `blocks.settings.options.schemas` can go. An option you set still wins.
