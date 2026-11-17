---
"better-supabase": patch
---

Doctor BS219 ignores a negated `?` and one inside `case`, BS345 checks only the upload key because the attachments read policy already checks the subject row, and BS346 accepts an `on` entry that carries its own `table`.
