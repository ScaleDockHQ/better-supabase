---
"better-supabase": minor
---

`field-encryption` rotates keys and says what they protect. Each `keyStatus()` entry now carries `keyCreatedAt`, `keyRotatedAt`, `lookupKeyCreatedAt`, the app table `columns` that owner's kind of key encrypts and the number of encrypted custom `fields`, still without key material. `rotateKey(owner)` (SQL `rotate_field_key`) replaces the data key in Vault and encrypts every value sealed under it again in one transaction, with the new `field_encryption.manage` key (owner and admin by default), and records `field_key.rotated`. Columns your own trigger seals with `field_seal` go in the new `blocks["field-encryption"].options.sealed` list so a rotation covers them. Run `better-supabase gen` and `db diff`; `gen.permissionCatalog` adds the key.
