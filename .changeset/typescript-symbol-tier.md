---
"better-supabase": patch
---

The CLI can use TypeScript 7.1 or newer, when your project has it installed, to find where a symbol is used and declared across files. `typescript` is now an optional peer (`>=5.0.0`); without 7.1 the codemods keep working file by file.
