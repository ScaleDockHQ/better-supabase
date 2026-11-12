---
"better-supabase": minor
---

Bookings series expand through the shared recurrence core, and `better-supabase/recurrence` exports `parseRrule` and `formatRrule`. `booking_series_starts` now calls `rrule_occurrences` (the `bookings` module requires `recurrence`), so a series keeps its local time across a daylight saving change exactly like a calendar event. Run `better-supabase upgrade` and `db diff` to pick up the new function. `parseRecurrence` and `formatRecurrence` keep their signatures; `formatRecurrence` now leaves out `INTERVAL=1`, and a malformed part such as `COUNT` without a value throws `Invalid RRULE part`. The digest loop moves into a shared helper that notifications call, and ADR 0719 replaces ADR 0197.

| Old                                                                                | New                                                               |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `booking_series_starts` loops over days in SQL                                     | `booking_series_starts` calls `better_supabase.rrule_occurrences` |
| Bookings parse RRULE text with their own parser                                    | `parseRrule` and `formatRrule` from `better-supabase/recurrence`  |
| `bookings` module requires `memberships`, `permissions`                            | also requires `recurrence`                                        |
| `formatRecurrence({ freq: "daily", interval: 1 })` returns `FREQ=DAILY;INTERVAL=1` | returns `FREQ=DAILY`                                              |
