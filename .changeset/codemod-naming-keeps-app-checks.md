---
"better-supabase": patch
---

`codemod naming` keeps the check constraints the app's own schema files and
seeds name on block tables (`alter table better_supabase.profiles add
constraint profiles_locale_check ...`). Its `bsb_` loop renamed them, and the
next schema diff renamed them back.
