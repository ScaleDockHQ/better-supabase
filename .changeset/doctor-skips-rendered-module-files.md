---
"better-supabase": patch
---

`doctor` no longer reports BS721 or BS722 for the module files the library renders under `supabase/schemas/_better_supabase`, and BS722 ignores repeated `create schema if not exists` and `create extension if not exists` statements, so a project that installs many blocks no longer gets thousands of duplicate-definition warnings.
