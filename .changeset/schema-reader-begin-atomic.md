---
"better-supabase": patch
---

The CLI's SQL reader keeps a `begin atomic ... end` function body and a multi-action rule
(`do also (...; ...)`) in one statement. It used to end a statement at every semicolon outside a
string, so doctor rules, the migration and upgrade commands and the codemods that read
statements saw the body as several statements, each with its own line number. A file whose parentheses or `begin atomic` never close still splits at every
semicolon, as before (ADR 1226).
