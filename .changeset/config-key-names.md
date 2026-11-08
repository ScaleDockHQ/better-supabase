---
"better-supabase": minor
---

Config keys have one spelling each. Rename them in `better-supabase.config.ts` (or run `better-supabase codemod naming`, which rewrites the same-parent keys); a config that keeps an old key is refused, with the new name in the message.

| Old                                                                                                | New                                                                                        |
| -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `subjects`                                                                                         | `recordTypes`                                                                              |
| `gen.recordTypes`                                                                                  | `gen.records`                                                                              |
| `gen.output`                                                                                       | `gen.file`                                                                                 |
| `database.seed.output`, `database.seed.sample.output`, `database.realtime.policies.output`         | `database.seed.file`, `database.seed.sample.file`, `database.realtime.policies.file`       |
| `tooling.env.output`, `tooling.keys.output`, `tooling.doctor.output`, `api.specs.outputs[].output` | `tooling.env.file`, `tooling.keys.file`, `tooling.doctor.file`, `api.specs.outputs[].file` |
| `integrations` (flat), `organization` (flat)                                                       | `adapters`, `auth.tenant`                                                                  |
| the `integrations` field of a preset                                                               | `adapters`                                                                                 |
