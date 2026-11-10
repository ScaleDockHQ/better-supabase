---
"better-supabase": patch
---

`better_supabase.session_active()` parses the token claims once per call instead of three times: it reads `sub` from the claims it already parsed rather than calling `auth.uid()`. Restrictive session policies run it once for each table a statement reads, so a query over many tables with a large token spends about a third of the time it did on the check. Run `better-supabase upgrade` and generate a migration to pick it up. An ended, expired or foreign session is still refused.
