---
"better-supabase": minor
---

Under an authorization provider, a block's default permission falls back from `<block>.<action>` to `<resource>.<action>` of its primary entity when the provider lists only the resource key, so a provider that names permissions after resources needs no `blocks.<name>.permissions` entries. An explicit entry still wins.
