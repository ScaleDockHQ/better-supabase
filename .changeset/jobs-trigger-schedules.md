---
"better-supabase": patch
---

The jobs docs show a database trigger that keeps a drain schedule current with `better_supabase.schedule_job`, so apps need no job that syncs rows into schedules, and an integration test runs a schedule such a trigger wrote, inserted by a signed-in user, through the drain route.
