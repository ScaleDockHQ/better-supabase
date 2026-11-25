---
"better-supabase": patch
---

The read policies of `funding`, `medications`, `observations`, `consents`, `field-history`, `pipelines`, `sla` and `deadlines` check a registry subject's permission as a set and call one generated function per module for the row check, so a signed-in read plans in about 2 ms instead of 15 to 20 ms. Run `better-supabase upgrade` and apply the new migration; each module adds a `*_subject_readable` function (`deadline_subject_row_readable` for deadlines) and replaces its read policies. The `funding_deliveries` read policy now compares the award's tenant with the delivery's tenant.
