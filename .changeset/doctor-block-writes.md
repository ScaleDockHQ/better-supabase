---
"better-supabase": minor
---

Doctor adds three checks.

- BS351 warns when app code writes a block's table directly with `.from("x").insert()`, `.update()`, `.upsert()` or `.delete()`, which skips the block's functions. Write through the API `createBlocks` returns.
- BS352 warns when one of your tables keeps a plain `credentials`, `token` or `secret` column while `field-encryption` or the `credentials` module is installed. Mark the column `encrypted: true`, or store it in Vault and keep a `credential_ref`.
- BS607 warns when the installed `better-supabase` is not the version your lockfile resolves, or when a block file or a `better_supabase.blocks` row records a block version newer than the installed release ships.
