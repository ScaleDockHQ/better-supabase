---
"better-supabase": minor
---

Presets write block instances, and doctor finds the 0.15 APIs left in app code.

- A preset object takes `instances`: `blocks` entries with `block`, `names`, `options`, `tables`, `on` and `uses`. An instance named after a block selects it; one with another `block` installs only what that block requires next to it. Your own `blocks` entry for the same key is merged over the preset's.
- `helpdesk` and `itsm` name the tasks block's work items `ticket` and its projects `issue`, and `property` adds a `maintenance` instance of tasks for maintenance requests. Set `blocks.tasks.names` in your config to keep the old names.
- The design JSON reads format 8, which adds the preset's `instances`, and `design-v1.json` and `config-v1.json` describe them.
- `presetBlocksSource` wires each extra instance in `lib/blocks.ts` (`maintenance: tasksBlock`), and the config source lists it.
- Doctor reports BS418 for imports of a renamed block or plugin subpath, an export named after a renamed block, and the record feature, leases maintenance and pass credit APIs 0.15 removed.
- The 0.14 to 0.15 guide ends with the upgrade order, and the consumer skill covers instances.
