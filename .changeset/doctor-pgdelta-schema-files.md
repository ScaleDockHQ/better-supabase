---
"better-supabase": minor
---

Doctor warns about two statements pg-delta can't order in `supabase/schemas`: bulk grants (`grant ... on all tables|routines|sequences in schema ... to anon|authenticated|public`, BS317), which can run after per-object revokes and re-open functions and tables, and `do` blocks that read the catalog to create objects (BS318), which run before the tables exist and create nothing. Both point to per-object statements, Supabase default privileges or per-table functions instead.
