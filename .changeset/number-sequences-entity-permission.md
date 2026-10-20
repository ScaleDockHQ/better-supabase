---
"better-supabase": minor
---

`number-sequences` entities take `permission`: the key `preview_number` checks for that entity, such as `invoices.write` for invoices and `quotes.write` for quotes. An entity without one keeps checking `blocks.number-sequences.permissions.assign`. `modulePermissionKeys` lists the entity keys, so `sql sync` and doctor check them against the authorization provider, and `ModulePermissionKey` gains an optional `setting` with the config path that sets the key.
