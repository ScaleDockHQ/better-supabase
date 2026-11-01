---
"better-supabase": minor
---

New reads: `hiring.jobs`, `hiring.applications`, `hiring.pipeline` and `hiring.close`, and `bookings.resources` and `bookings.services`. They come from the new SQL functions `list_jobs`, `list_applications`, `list_booking_resources` and `list_booking_services`, which run as the caller. Run `better-supabase upgrade` and apply the migration to get them.
