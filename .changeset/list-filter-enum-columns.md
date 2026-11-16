---
"better-supabase": patch
---

A text list filter, such as `status` on `list_teams`, `page_employees` or `page_invoices`, now
compares the column as text, so it works when the app keeps that column as an enum or a domain
instead of failing with "operator does not exist". Run `better-supabase upgrade` to rewrite the
block functions.
