---
"better-supabase": minor
---

`better-supabase/preset` describes an app as a preset: a block selection plus its conventions (framework, platforms, casing, id type, scope, tenant name, access model, API schema and integrations). `encodePreset` and `decodePreset` turn one into a short code, and `resolvePreset` returns every block to install with the reason it is there, the soft integrations between them and the conflicts. It reads a generated catalog of the blocks, so it runs in the browser. The named presets are `minimal`, `saas`, `crm`, `projects`, `commerce`, `scheduling`, `ai` and `everything`.

`defineConfig({ preset, blocks })` takes a named preset, a code or a `/create?preset=` URL and expands it into `blocks` and its conventions first; the keys you set win. The docs Recipes section is now Presets, at `/docs/presets`.
