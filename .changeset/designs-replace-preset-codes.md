---
"better-supabase": minor
---

Breaking: designs replace preset codes. The config's `preset` key takes a preset name or an object with the conventions that differ from the defaults and the blocks, a Create URL is `/create?preset=<name>` or `/create?design=<code>` with the preset inside the design (format 7), and a design file is the design JSON with its preset. `init`, `add` and `blocks list` stop on a 0.14 code and name `better-supabase codemod 0.15`, which converts the config's code and `*.design.json` files.

| 0.14                                         | 0.15                                                    |
| -------------------------------------------- | ------------------------------------------------------- |
| `encodePreset(preset)`                       | `presetSpec(preset)` or `createUrl(resolved)`           |
| `decodePreset(code)`                         | `presetAndDesignOf(input)` or `presetOfSpec(value)`     |
| `defaultPresetCode()`                        | `defaultPreset()`                                       |
| `withPresetField(preset, key, value)`        | `presetFromSpec({ ...presetSpec(preset), key: value })` |
| `designConfigSource(resolved, design, code)` | `presetConfigSource(resolved, design)` (async)          |
| `designInstallCommand(resolved, code)`       | `presetInstallCommand(resolved, design)` (async)        |
| `designApplyCommand(resolved, code)`         | `presetApplyCommand(resolved, design)` (async)          |

`isPresetCode`, `PRESET_BLOCKS`, `PRESET_FIELDS`, `PRESET_VERSION` and `DecodedPreset` are removed; `CONVENTION_FIELDS` lists the convention fields. The docs page `/docs/presets/codes` moves to `/docs/presets/designs`.
