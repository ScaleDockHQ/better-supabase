---
"better-supabase": patch
---

`field_seal` returns a value that already starts with `bsf1:` unchanged, so sealing it again does not wrap the ciphertext.
