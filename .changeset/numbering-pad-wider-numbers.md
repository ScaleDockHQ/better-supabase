---
"better-supabase": patch
---

`{n:W}` in a numbering format pads to at least W digits and no longer cuts a wider number, so a counter that outgrows its width keeps issuing unique numbers instead of repeating one. Run `better-supabase upgrade` to regenerate the numbering module.
