---
"better-supabase": patch
---

`record_inbound` now works as a real `service_role`. The `contacts` SQL module moves from version 2 to 3 and grants `resolve_person` to `service_role`, and the `inbox` module moves from version 9 to 10 so `record_inbound` runs as `security definer`. Run `better-supabase upgrade`.
