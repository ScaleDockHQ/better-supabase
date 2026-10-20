---
"better-supabase": patch
---

`number-sequences` refuses a client that writes `sequenceColumn` with `NUMBER_MANUAL`, as it already did for `column`. A signed-in user could send the bare number on a draft, which stayed visible until the trigger overwrote it on issue. Only the trigger and the service role write it now.
