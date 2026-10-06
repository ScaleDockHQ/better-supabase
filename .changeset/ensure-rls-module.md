---
"better-supabase": minor
---

The `ensure-rls` SQL module (`better-supabase sql add ensure-rls`) installs an event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a table added in a migration or the SQL editor is never exposed through the Data API without RLS. The trigger function lives in `better_supabase` and nobody but the owner can execute it.
