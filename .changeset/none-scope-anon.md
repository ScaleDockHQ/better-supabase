---
"better-supabase": minor
---

The `none` scope refuses anonymous sign-ins: its read checks and `can` conditions require a user whose `is_anonymous` claim is not true. Run `better-supabase upgrade` and generate a migration (ADR 0104).
