---
"better-supabase": minor
---

Blocks can declare plan limits and meters. A manifest's new `limits` and
`meters` name the methods that check a `usage` quota before they run (they
return `quota_exceeded` with the `meter` and `limit`) and the meter a
successful call records. Turn it on with `createBlocks({ metering: true })`
with the `usage` block in the set; it is off by default. `usage` now provides a
`meter` port, `organizations.invite` declares a limit on `seats`, and
`api-keys.create` a limit and meter on `api_keys_created`. `BlockQuota` is the
one shape of a `quota` option (`blocks.drive.options.quota`). No option or
error code is renamed.
