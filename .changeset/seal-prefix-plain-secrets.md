---
"better-supabase": patch
---

The app table seal trigger no longer seals a value that already carries the `bsf1:` prefix, so an upsert stores its encrypted values once instead of wrapping the `excluded` ciphertext a second time. A row that moves to another owner with the value unchanged is still sealed again with the new owner's key, and a lookup hash is rewritten when its ciphertext changes. Run `better-supabase upgrade` and `supabase:diff` to pick up the new trigger.

Doctor's BS352 (plain secret column) now also reports columns that end in `header_value`, such as `auth_header_value`. It skips columns marked in an `@bsb encrypted` table tag, and columns that a `before` row trigger seals when its function is listed in the new `tooling.doctor.sealTriggers` option.
