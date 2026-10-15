---
"better-supabase": minor
---

The CLI starts and changes projects from presets. `init --preset <name|code|url>` writes the config with `preset`, the module files of every block it installs and a `lib/blocks.ts` that wires their clients, and prints the registry glue for the framework. `apply --preset` sets `preset` in an existing config (or, with `--only blocks`, lists its blocks; with `--only conventions`, takes the conventions alone), shows the diff and writes the modules. `preset decode` and `preset info` print what a code holds and how the config differs from its preset, and `blocks list`, `blocks view` and `blocks search` read the block catalog.

`add <block...>` now adds blocks: it lists them in `blocks`, writes their modules and what they require, wires their clients into `lib/blocks.ts` and names their registry glue. The framework glue moves to `add --framework <integration,...>`; `add` without arguments still sets up the integrations the config lists. In a terminal, `init` first asks for a preset. `better-supabase/preset` adds `presetApplyCommand`, `presetGlue` and `glueCommand`, and `presetInstallCommand` now returns `init --preset <code>`.
