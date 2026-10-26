---
"better-supabase": patch
---

Authorization templates are now checked by a tokenizer instead of regular expressions. A `;` or `--` inside a string or quoted identifier no longer counts, and a tagged dollar quote (`$tag$`), a block comment, an unterminated string or a stray `{` is refused. `gen` refuses an unsafe template before it fills the placeholders.
