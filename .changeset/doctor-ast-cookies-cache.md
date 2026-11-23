---
"better-supabase": patch
---

Read the session cookie and cache source rules (BS412, BS608, BS610, BS611, BS640) from the syntax tree. A comment, a string or a type annotation that mentions `encode: "tokens-only"`, `bsb.remote(`, `cookies()` or `bsb.admin(` no longer counts, and a function that follows such a string is still found. Findings, codes and lines stay the same for real code.
